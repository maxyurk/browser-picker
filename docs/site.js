"use strict";

// Everything essential is plain HTML. These controls are optional enhancements.
const preview = document.querySelector("#picker-preview");
const previewControls = document.querySelector(".preview-controls");
const previewCaption = document.querySelector("#preview-caption");
const rememberImage = new Image();
rememberImage.src = "assets/picker-remember.png";

previewControls.hidden = false;
for (const button of previewControls.querySelectorAll("button")) {
  button.addEventListener("click", () => {
    const remember = button.dataset.pickerMode === "remember";
    preview.src = remember ? "assets/picker-remember.png" : "assets/picker.png";
    preview.alt = remember
      ? "Holding Command checks Always use this browser for this website and reveals Command-number shortcuts"
      : "Browser Picker showing Orion, Chrome, Chrome Work, and Safari for a GitHub link";
    previewCaption.textContent = remember
      ? "Hold Command. Choose a browser. Remember the website."
      : "The real app, with an illustrative Work profile.";
    for (const control of previewControls.querySelectorAll("button")) {
      control.setAttribute("aria-pressed", String(control === button));
    }
  });
}

const copyButton = document.querySelector("#copy-command");
const copyStatus = document.querySelector("#copy-status");
const command = document.querySelector("#install-command");
if (navigator.clipboard?.writeText) {
  copyButton.hidden = false;
  copyButton.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(command.textContent.trim());
      copyStatus.textContent = "Copied. Run it from the project directory.";
    } catch {
      copyStatus.textContent = "Select the command above and copy it manually.";
    }
  });
}

// A local preview has no made-up repository URL. Standard GitHub Pages hosting
// can infer it; a public metadata URL handles custom domains and other setups.
function repositoryURL() {
  const configured = document.querySelector('meta[name="repository"]').content.trim();
  if (configured) {
    try {
      const url = new URL(configured);
      if (url.protocol === "https:" && url.hostname === "github.com" && /^\/[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\/?$/.test(url.pathname) && !url.username && !url.password && !url.search && !url.hash) {
        return url.origin + url.pathname.replace(/\/$/, "");
      }
    } catch { /* Leave source links hidden for invalid configuration. */ }
    return null;
  }
  const match = location.hostname.match(/^([A-Za-z0-9-]+)\.github\.io$/i);
  if (!match) return null;
  const project = location.pathname.split("/").filter(Boolean)[0];
  const repository = !project || project === "index.html" ? `${match[1]}.github.io` : project;
  if (!/^[A-Za-z0-9_.-]+$/.test(repository)) return null;
  return `https://github.com/${match[1]}/${repository}`;
}

const repository = repositoryURL();
if (repository) {
  for (const link of document.querySelectorAll(".repository-link")) {
    link.href = repository;
    link.hidden = false;
  }
  const sourceDownload = document.querySelector(".source-download");
  sourceDownload.href = `${repository}/archive/HEAD.zip`;
  sourceDownload.hidden = false;
}
