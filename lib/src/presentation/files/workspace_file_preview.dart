/// 读取工作区文件后用于只读预览的结果对象，包含内容或明确的失败原因。
/// The result of reading a workspace file for the read-only preview.
class WorkspaceFilePreview {
  const WorkspaceFilePreview.content(this.content) : error = null;

  const WorkspaceFilePreview.error(this.error) : content = null;

  final String? content;
  final String? error;
}
