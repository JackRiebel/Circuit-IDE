enum MessageRole {
  user('user'),
  assistant('assistant'),
  system('system'),
  tool('tool');

  const MessageRole(this.value);
  final String value;
}
