// Runs inside the Office dialog after the person confirms: hand the token to the task pane.
const el = document.getElementById("connected");
const payload = JSON.stringify({ token: el.dataset.token, name: el.dataset.name });
const status = document.getElementById("connect-status");

if (window.Office?.onReady) {
  Office.onReady(() => {
    try { Office.context.ui.messageParent(payload); }
    catch { status.textContent = "Connected. You can close this window."; }
  });
} else {
  status.textContent = "Connected. Open this from the Skill Capture add-in in Office to finish.";
}
