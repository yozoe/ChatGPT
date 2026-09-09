/// 悬停触发的弹层在显示前需要保持指针停留的时长。
/// The dwell time before a hover-triggered popup becomes visible.
///
/// Keeps tooltips and custom hover cards aligned with the Codex desktop
/// interaction rhythm, so passing the pointer across controls does not cause
/// distracting transient popups.
const codexHoverPopupDelay = Duration(milliseconds: 450);
