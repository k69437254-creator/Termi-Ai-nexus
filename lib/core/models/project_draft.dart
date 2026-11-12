class ProjectDraft {
  const ProjectDraft({
    required this.id,
    required this.title,
    required this.request,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String request;
  final DateTime createdAt;
}
