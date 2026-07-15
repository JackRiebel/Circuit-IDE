"""
Unit tests for FileTools.

Tests file operations: read, write, edit, list, search, run_command.
"""

import os
import pytest
from pathlib import Path


class TestReadFile:
    """Tests for FileTools.read_file()"""

    def test_read_existing_file(self, file_tools, project_dir):
        """Should read an existing file with line numbers."""
        result = file_tools.read_file({"path": "src/main.py"}, confirmed=True)

        assert "def main():" in result
        assert "Hello, World!" in result
        # Should have line numbers
        assert "1|" in result or "1 |" in result

    def test_read_nonexistent_file(self, file_tools):
        """Should return helpful error for missing file."""
        result = file_tools.read_file({"path": "nonexistent.py"}, confirmed=True)

        assert "Error" in result or "not found" in result.lower()

    def test_read_file_with_line_range(self, file_tools, project_dir):
        """Should read specific line range."""
        # Create a file with many lines
        test_file = project_dir / "multiline.txt"
        test_file.write_text("\n".join(f"Line {i}" for i in range(1, 101)))

        result = file_tools.read_file({
            "path": "multiline.txt",
            "start_line": 10,
            "end_line": 15
        }, confirmed=True)

        assert "Line 10" in result
        assert "Line 15" in result
        assert "Line 9" not in result
        assert "Line 16" not in result

    def test_read_directory_returns_error(self, file_tools):
        """Should return error when trying to read a directory."""
        result = file_tools.read_file({"path": "src"}, confirmed=True)

        assert "directory" in result.lower() or "Error" in result

    def test_read_file_outside_working_dir(self, file_tools):
        """Should prevent path traversal attacks."""
        result = file_tools.read_file({"path": "../../../etc/passwd"}, confirmed=True)

        assert "Error" in result
        assert "outside" in result.lower() or "traversal" in result.lower()

    def test_read_large_file_truncation(self, file_tools, project_dir):
        """Should truncate very large files."""
        # Create a file with 1000 lines
        large_file = project_dir / "large.txt"
        large_file.write_text("\n".join(f"Line {i}" for i in range(1, 1001)))

        result = file_tools.read_file({"path": "large.txt"}, confirmed=True)

        # Should be truncated
        assert "truncated" in result.lower() or "more lines" in result.lower()

    def test_read_empty_file(self, file_tools, project_dir):
        """Should handle empty files."""
        empty_file = project_dir / "empty.txt"
        empty_file.write_text("")

        result = file_tools.read_file({"path": "empty.txt"}, confirmed=True)

        assert "empty" in result.lower() or result.strip() == ""


class TestWriteFile:
    """Tests for FileTools.write_file()"""

    def test_write_requires_confirmation(self, file_tools):
        """Should require confirmation by default."""
        result = file_tools.write_file({
            "path": "new_file.txt",
            "content": "test content"
        }, confirmed=False)

        assert "NEEDS_CONFIRMATION" in result

    def test_write_new_file(self, file_tools, project_dir):
        """Should create a new file."""
        result = file_tools.write_file({
            "path": "new_file.txt",
            "content": "Hello, Test!"
        }, confirmed=True)

        assert "Successfully" in result or "wrote" in result.lower()
        assert (project_dir / "new_file.txt").exists()
        assert (project_dir / "new_file.txt").read_text() == "Hello, Test!"

    def test_write_creates_directories(self, file_tools, project_dir):
        """Should create parent directories if needed."""
        result = file_tools.write_file({
            "path": "new/nested/dir/file.txt",
            "content": "nested content"
        }, confirmed=True)

        assert "Successfully" in result or "wrote" in result.lower()
        assert (project_dir / "new/nested/dir/file.txt").exists()

    def test_write_overwrites_existing(self, file_tools, project_dir):
        """Should overwrite existing file."""
        existing = project_dir / "existing.txt"
        existing.write_text("old content")

        file_tools.write_file({
            "path": "existing.txt",
            "content": "new content"
        }, confirmed=True)

        assert existing.read_text() == "new content"

    def test_write_outside_working_dir(self, file_tools):
        """Should prevent writing outside working directory."""
        result = file_tools.write_file({
            "path": "../../../tmp/evil.txt",
            "content": "malicious"
        }, confirmed=True)

        assert "Error" in result


class TestEditFile:
    """Tests for FileTools.edit_file()"""

    def test_edit_requires_confirmation(self, file_tools, project_dir):
        """Should require confirmation by default."""
        result = file_tools.edit_file({
            "path": "src/main.py",
            "old_text": "Hello",
            "new_text": "Goodbye"
        }, confirmed=False)

        assert "NEEDS_CONFIRMATION" in result

    def test_edit_replaces_text(self, file_tools, project_dir):
        """Should replace text in file."""
        result = file_tools.edit_file({
            "path": "src/main.py",
            "old_text": "Hello, World!",
            "new_text": "Hello, Test!"
        }, confirmed=True)

        assert "Successfully" in result or "edited" in result.lower()
        content = (project_dir / "src/main.py").read_text()
        assert "Hello, Test!" in content
        assert "Hello, World!" not in content

    def test_edit_text_not_found(self, file_tools, project_dir):
        """Should return error when text not found."""
        result = file_tools.edit_file({
            "path": "src/main.py",
            "old_text": "this text does not exist",
            "new_text": "replacement"
        }, confirmed=True)

        # Check that the error message indicates text wasn't found
        result_lower = result.lower()
        assert any(phrase in result_lower for phrase in [
            "not found", "could not find", "wasn't found"
        ])

    def test_edit_multiple_matches(self, file_tools, project_dir):
        """Should error when multiple matches found."""
        # Create file with duplicate text
        dupe_file = project_dir / "duplicates.txt"
        dupe_file.write_text("hello\nworld\nhello\n")

        result = file_tools.edit_file({
            "path": "duplicates.txt",
            "old_text": "hello",
            "new_text": "goodbye"
        }, confirmed=True)

        assert "Error" in result or "multiple" in result.lower() or "2" in result

    def test_edit_nonexistent_file(self, file_tools):
        """Should return error for nonexistent file."""
        result = file_tools.edit_file({
            "path": "nonexistent.py",
            "old_text": "old",
            "new_text": "new"
        }, confirmed=True)

        assert "Error" in result or "not found" in result.lower()

    def test_edit_preserves_whitespace(self, file_tools, project_dir):
        """Should preserve exact whitespace in replacement."""
        ws_file = project_dir / "whitespace.py"
        ws_file.write_text("def foo():\n    pass\n")

        file_tools.edit_file({
            "path": "whitespace.py",
            "old_text": "    pass",
            "new_text": "    return True"
        }, confirmed=True)

        content = ws_file.read_text()
        assert "    return True" in content


class TestListFiles:
    """Tests for FileTools.list_files()"""

    def test_list_all_python_files(self, file_tools, project_dir):
        """Should list Python files recursively."""
        result = file_tools.list_files({"pattern": "**/*.py"}, confirmed=True)

        assert "main.py" in result
        assert "utils.py" in result
        assert "__init__.py" in result

    def test_list_current_dir_only(self, file_tools, project_dir):
        """Should list files in current directory only with non-recursive pattern."""
        result = file_tools.list_files({"pattern": "*.md"}, confirmed=True)

        assert "README.md" in result

    def test_list_no_matches(self, file_tools):
        """Should return appropriate message when no matches."""
        result = file_tools.list_files({"pattern": "*.xyz"}, confirmed=True)

        assert "No files found" in result or "0" in result

    def test_list_excludes_hidden(self, file_tools):
        """Should exclude hidden directories like .git."""
        result = file_tools.list_files({"pattern": "**/*"}, confirmed=True)

        assert ".git" not in result


class TestSearchFiles:
    """Tests for FileTools.search_files()"""

    def test_search_finds_pattern(self, file_tools, project_dir):
        """Should find regex pattern in files."""
        result = file_tools.search_files({
            "pattern": "def main",
            "file_pattern": "**/*.py"
        }, confirmed=True)

        assert "main.py" in result
        assert "def main" in result

    def test_search_case_insensitive(self, file_tools, project_dir):
        """Should support case-insensitive search."""
        result = file_tools.search_files({
            "pattern": "HELLO",
            "case_sensitive": False
        }, confirmed=True)

        assert "Hello" in result or "main.py" in result

    def test_search_no_matches(self, file_tools):
        """Should return appropriate message when no matches."""
        result = file_tools.search_files({
            "pattern": "xyzzy_not_found_pattern"
        }, confirmed=True)

        assert "No matches" in result or "0" in result

    def test_search_invalid_regex(self, file_tools):
        """Should handle invalid regex gracefully."""
        result = file_tools.search_files({
            "pattern": "[invalid("
        }, confirmed=True)

        assert "Error" in result or "Invalid" in result


class TestRunCommand:
    """Tests for FileTools.run_command()"""

    def test_run_simple_command(self, file_tools):
        """Should run a simple command."""
        result = file_tools.run_command({
            "command": "echo 'Hello, World!'"
        }, confirmed=True)

        assert "Hello, World!" in result

    def test_run_command_with_output(self, file_tools, project_dir):
        """Should capture command output."""
        result = file_tools.run_command({
            "command": "ls"
        }, confirmed=True)

        assert "README.md" in result or "src" in result

    def test_run_command_timeout(self, file_tools):
        """Should handle command timeout."""
        result = file_tools.run_command({
            "command": "sleep 10",
            "timeout": 1
        }, confirmed=True)

        assert "timeout" in result.lower() or "timed out" in result.lower()

    def test_dangerous_command_requires_confirmation(self, file_tools):
        """Should require confirmation for dangerous commands."""
        result = file_tools.run_command({
            "command": "rm -rf /"
        }, confirmed=False)

        assert "NEEDS_CONFIRMATION" in result

    def test_run_command_in_working_dir(self, file_tools, project_dir):
        """Should run command in working directory."""
        result = file_tools.run_command({
            "command": "pwd"
        }, confirmed=True)

        assert str(project_dir) in result or project_dir.name in result


class TestHtmlToMarkdown:
    """Tests for FileTools.html_to_markdown()"""

    def test_convert_simple_html(self, file_tools, project_dir):
        """Should convert simple HTML to markdown."""
        html_file = project_dir / "test.html"
        html_file.write_text("""
        <html>
        <head><title>Test</title></head>
        <body>
            <h1>Hello World</h1>
            <p>This is a paragraph.</p>
            <ul>
                <li>Item 1</li>
                <li>Item 2</li>
            </ul>
        </body>
        </html>
        """)

        result = file_tools.html_to_markdown({
            "input_path": "test.html",
            "output_path": "test.md"
        }, confirmed=True)

        assert "Successfully" in result
        md_content = (project_dir / "test.md").read_text()
        assert "# Hello World" in md_content
        assert "This is a paragraph" in md_content

    def test_convert_nonexistent_file(self, file_tools):
        """Should error on nonexistent input file."""
        result = file_tools.html_to_markdown({
            "input_path": "nonexistent.html",
            "output_path": "output.md"
        }, confirmed=True)

        assert "Error" in result or "not found" in result.lower()


class TestBackupManager:
    """Tests for BackupManager."""

    def test_backup_creates_backup(self, backup_manager, project_dir):
        """Should create backup of file."""
        test_file = project_dir / "backup_test.txt"
        test_file.write_text("original content")

        backup_manager.backup("backup_test.txt")

        # Modify the original
        test_file.write_text("modified content")

        # Backup should exist and contain original
        backup = backup_manager.get_backup("backup_test.txt")
        assert backup is not None
        assert backup == "original content"

    def test_restore_from_backup(self, backup_manager, project_dir):
        """Should restore file from backup."""
        test_file = project_dir / "restore_test.txt"
        test_file.write_text("original")

        backup_manager.backup("restore_test.txt")
        test_file.write_text("modified")

        success = backup_manager.restore("restore_test.txt")

        assert success
        assert test_file.read_text() == "original"

    def test_list_backups(self, backup_manager, project_dir):
        """Should list all backed up files."""
        (project_dir / "file1.txt").write_text("content1")
        (project_dir / "file2.txt").write_text("content2")

        backup_manager.backup("file1.txt")
        backup_manager.backup("file2.txt")

        backups = backup_manager.list_backups()

        assert "file1.txt" in backups or len(backups) >= 2
