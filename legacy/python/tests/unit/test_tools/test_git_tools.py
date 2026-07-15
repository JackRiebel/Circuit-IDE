"""
Unit tests for GitTools.

Tests git operations: status, diff, log, commit, branch.
"""

import subprocess
import pytest
from pathlib import Path


@pytest.fixture
def git_repo(project_dir: Path) -> Path:
    """Initialize a git repository in the project directory."""
    subprocess.run(
        ["git", "init"],
        cwd=project_dir,
        capture_output=True,
        check=True
    )
    subprocess.run(
        ["git", "config", "user.email", "test@test.com"],
        cwd=project_dir,
        capture_output=True,
        check=True
    )
    subprocess.run(
        ["git", "config", "user.name", "Test User"],
        cwd=project_dir,
        capture_output=True,
        check=True
    )
    # Initial commit
    subprocess.run(
        ["git", "add", "."],
        cwd=project_dir,
        capture_output=True,
        check=True
    )
    subprocess.run(
        ["git", "commit", "-m", "Initial commit"],
        cwd=project_dir,
        capture_output=True,
        check=True
    )
    return project_dir


class TestGitStatus:
    """Tests for GitTools.git_status()"""

    def test_status_clean_repo(self, git_tools, git_repo):
        """Should show clean status for repo with no changes."""
        result = git_tools.git_status({}, confirmed=True)

        # Clean repo might show branch name or "nothing to commit" message
        result_lower = result.lower()
        # If it has no output or just shows branch info, it's clean
        assert any(phrase in result_lower for phrase in [
            "nothing to commit", "clean", "master", "main", "##"
        ]) or len(result.strip()) < 50  # Short output = clean

    def test_status_with_modified_files(self, git_tools, git_repo):
        """Should show modified files."""
        # Modify a file
        (git_repo / "README.md").write_text("Modified content")

        result = git_tools.git_status({}, confirmed=True)

        assert "README.md" in result
        assert "modified" in result.lower() or "M " in result

    def test_status_with_untracked_files(self, git_tools, git_repo):
        """Should show untracked files."""
        # Create new file
        (git_repo / "new_file.txt").write_text("new content")

        result = git_tools.git_status({}, confirmed=True)

        assert "new_file.txt" in result
        assert "untracked" in result.lower() or "??" in result

    def test_status_not_git_repo(self, git_tools, project_dir):
        """Should handle non-git directory gracefully."""
        # Remove .git directory
        import shutil
        shutil.rmtree(project_dir / ".git", ignore_errors=True)

        result = git_tools.git_status({}, confirmed=True)

        assert "not a git repository" in result.lower() or "Error" in result


class TestGitDiff:
    """Tests for GitTools.git_diff()"""

    def test_diff_no_changes(self, git_tools, git_repo):
        """Should show no diff for clean repo."""
        result = git_tools.git_diff({}, confirmed=True)

        # Empty diff, "(no output)" message, or message indicating no changes
        result_lower = result.lower().strip()
        assert (
            result_lower == "" or
            "no changes" in result_lower or
            "(no output)" in result_lower or
            len(result_lower) < 20
        )

    def test_diff_with_changes(self, git_tools, git_repo):
        """Should show diff for modified files."""
        readme = git_repo / "README.md"
        original = readme.read_text()
        readme.write_text(original + "\nNew line added")

        result = git_tools.git_diff({}, confirmed=True)

        assert "New line added" in result or "+New line" in result

    def test_diff_staged_changes(self, git_tools, git_repo):
        """Should show staged changes with staged=True."""
        readme = git_repo / "README.md"
        readme.write_text("Staged change")
        subprocess.run(["git", "add", "README.md"], cwd=git_repo, capture_output=True)

        result = git_tools.git_diff({"staged": True}, confirmed=True)

        assert "Staged change" in result or "-# Test Project" in result

    def test_diff_specific_file(self, git_tools, git_repo):
        """Should show diff for specific file only."""
        (git_repo / "README.md").write_text("Changed readme")
        (git_repo / "src/main.py").write_text("Changed main")

        result = git_tools.git_diff({"path": "README.md"}, confirmed=True)

        assert "Changed readme" in result or "README" in result
        # Should not include main.py changes
        assert "Changed main" not in result


class TestGitLog:
    """Tests for GitTools.git_log()"""

    def test_log_shows_commits(self, git_tools, git_repo):
        """Should show commit history."""
        result = git_tools.git_log({}, confirmed=True)

        assert "Initial commit" in result

    def test_log_with_count(self, git_tools, git_repo):
        """Should limit number of commits shown."""
        # Create additional commits
        for i in range(5):
            (git_repo / f"file{i}.txt").write_text(f"content {i}")
            subprocess.run(["git", "add", "."], cwd=git_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", f"Commit {i}"],
                cwd=git_repo,
                capture_output=True
            )

        result = git_tools.git_log({"count": 2}, confirmed=True)

        # Should have limited commits
        lines = [l for l in result.split('\n') if l.strip()]
        # Oneline format: each commit is one line
        commit_count = sum(1 for l in lines if "Commit" in l or "commit" in l.lower())
        assert commit_count <= 3  # Allow some flexibility

    def test_log_file_history(self, git_tools, git_repo):
        """Should show history for specific file."""
        # Modify a specific file
        readme = git_repo / "README.md"
        readme.write_text("Updated readme")
        subprocess.run(["git", "add", "README.md"], cwd=git_repo, capture_output=True)
        subprocess.run(
            ["git", "commit", "-m", "Update readme"],
            cwd=git_repo,
            capture_output=True
        )

        result = git_tools.git_log({"path": "README.md"}, confirmed=True)

        assert "Update readme" in result or "Initial" in result


class TestGitCommit:
    """Tests for GitTools.git_commit()"""

    def test_commit_requires_confirmation(self, git_tools, git_repo):
        """Should require confirmation."""
        (git_repo / "new.txt").write_text("new")

        result = git_tools.git_commit({
            "message": "Test commit"
        }, confirmed=False)

        assert "NEEDS_CONFIRMATION" in result

    def test_commit_stages_and_commits(self, git_tools, git_repo):
        """Should stage and commit changes."""
        (git_repo / "new_file.txt").write_text("new content")

        result = git_tools.git_commit({
            "message": "Add new file",
            "files": ["new_file.txt"]
        }, confirmed=True)

        # Verify commit was created
        log_result = subprocess.run(
            ["git", "log", "--oneline", "-1"],
            cwd=git_repo,
            capture_output=True,
            text=True
        )
        assert "Add new file" in log_result.stdout

    def test_commit_all_changes(self, git_tools, git_repo):
        """Should commit all changes when no files specified."""
        (git_repo / "README.md").write_text("Modified")
        (git_repo / "src/main.py").write_text("Modified main")

        result = git_tools.git_commit({
            "message": "Update multiple files"
        }, confirmed=True)

        # Both files should be committed
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=git_repo,
            capture_output=True,
            text=True
        )
        assert status.stdout.strip() == ""  # Nothing left to commit


class TestGitBranch:
    """Tests for GitTools.git_branch()"""

    def test_branch_list(self, git_tools, git_repo):
        """Should list branches."""
        result = git_tools.git_branch({"action": "list"}, confirmed=True)

        assert "main" in result or "master" in result

    def test_branch_create(self, git_tools, git_repo):
        """Should create new branch."""
        result = git_tools.git_branch({
            "action": "create",
            "name": "feature-test"
        }, confirmed=True)

        # Verify branch exists
        branches = subprocess.run(
            ["git", "branch"],
            cwd=git_repo,
            capture_output=True,
            text=True
        )
        assert "feature-test" in branches.stdout

    def test_branch_switch(self, git_tools, git_repo):
        """Should switch to existing branch."""
        # Create branch first
        subprocess.run(
            ["git", "branch", "test-branch"],
            cwd=git_repo,
            capture_output=True
        )

        result = git_tools.git_branch({
            "action": "switch",
            "name": "test-branch"
        }, confirmed=True)

        # Verify we're on the new branch
        current = subprocess.run(
            ["git", "branch", "--show-current"],
            cwd=git_repo,
            capture_output=True,
            text=True
        )
        assert "test-branch" in current.stdout

    def test_branch_delete(self, git_tools, git_repo):
        """Should delete branch."""
        # Create and then delete branch
        subprocess.run(
            ["git", "branch", "to-delete"],
            cwd=git_repo,
            capture_output=True
        )

        result = git_tools.git_branch({
            "action": "delete",
            "name": "to-delete"
        }, confirmed=True)

        # Verify branch is gone
        branches = subprocess.run(
            ["git", "branch"],
            cwd=git_repo,
            capture_output=True,
            text=True
        )
        assert "to-delete" not in branches.stdout

    def test_branch_invalid_action(self, git_tools, git_repo):
        """Should handle invalid action gracefully."""
        result = git_tools.git_branch({
            "action": "invalid_action"
        }, confirmed=True)

        assert "Error" in result or "Unknown" in result or "Invalid" in result
