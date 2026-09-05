/// The result of reading a workspace file for the read-only preview.
class WorkspaceFilePreview {
  const WorkspaceFilePreview.content(this.content) : error = null;

  const WorkspaceFilePreview.error(this.error) : content = null;

  final String? content;
  final String? error;
}
