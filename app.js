(async function () {
  let CATS = [];
  let ARTWORKS = [];

  try {
    const res = await fetch("data/manifest.json", { cache: "no-store" });
    const manifest = await res.json();
    CATS = manifest.categories || [];
    ARTWORKS = manifest.artworks || [];
  } catch (err) {
    console.error("Failed to load data/manifest.json", err);
    document.getElementById("portals").innerHTML =
      '<p style="color:var(--text-dim);padding:20px;">Could not load the gallery data. Try refreshing.</p>';
    return;
  }

  let activeCat = "all";
  let currentList = ARTWORKS.slice();
  let lbIndex = 0;
  let r18Unlocked = sessionStorage.getItem("r18-ok") === "1";
  let pendingIndex = null;

  const portalsEl = document.getElementById("portals");
  const tabsEl = document.getElementById("tabs");
  const gridEl = document.getElementById("grid");
  const heroView = document.getElementById("heroView");
  const galleryView = document.getElementById("galleryView");
  const lightbox = document.getElementById("lightbox");
  const lbImg = document.getElementById("lbImg");
  const lbTitle = document.getElementById("lbTitle");
  const lbCat = document.getElementById("lbCat");
  const r18Confirm = document.getElementById("r18Confirm");

  function catLabel(key) {
    const found = CATS.find((c) => c.key === key);
    return found ? found.label : key;
  }

  function renderPortals() {
    portalsEl.innerHTML = "";
    CATS.forEach((cat) => {
      const count =
        cat.key === "all"
          ? ARTWORKS.length
          : ARTWORKS.filter((a) => a.cat === cat.key).length;
      const btn = document.createElement("button");
      btn.className = "portal";
      btn.style.setProperty("--img", "url(" + cat.banner + ")");
      btn.innerHTML =
        '<span class="portal-label">' + cat.label + "<em>" + count + "</em></span>";
      btn.addEventListener("click", () => enterCategory(cat.key));
      portalsEl.appendChild(btn);
    });
  }

  function enterCategory(key) {
    activeCat = key;
    heroView.hidden = true;
    galleryView.hidden = false;
    renderTabs();
    renderGrid();
    window.scrollTo(0, 0);
  }
  function goHome() {
    galleryView.hidden = true;
    heroView.hidden = false;
    window.scrollTo(0, 0);
  }
  document.getElementById("backBtn").addEventListener("click", goHome);

  function renderTabs() {
    tabsEl.innerHTML = "";
    CATS.forEach((cat) => {
      const count =
        cat.key === "all"
          ? ARTWORKS.length
          : ARTWORKS.filter((a) => a.cat === cat.key).length;
      const btn = document.createElement("button");
      btn.className = "tab";
      btn.type = "button";
      btn.role = "tab";
      btn.setAttribute("aria-selected", cat.key === activeCat ? "true" : "false");
      btn.innerHTML = cat.label + '<span class="count">' + count + "</span>";
      btn.addEventListener("click", () => {
        activeCat = cat.key;
        renderTabs();
        renderGrid();
      });
      tabsEl.appendChild(btn);
    });
  }

  function renderGrid() {
    gridEl.innerHTML = "";
    currentList =
      activeCat === "all" ? ARTWORKS.slice() : ARTWORKS.filter((a) => a.cat === activeCat);

    if (currentList.length === 0) {
      gridEl.innerHTML = '<p class="empty-state">Nothing here yet.</p>';
      return;
    }

    currentList.forEach((art, i) => {
      const card = document.createElement("div");
      card.className = "card" + (art.r18 ? " is-r18" : "");
      card.innerHTML =
        '<img src="' + art.src + '" alt="' + art.title + '" loading="lazy" />' +
        (art.r18
          ? '<div class="r18-badge"><span class="tag">R-18</span><span class="hint">Tap to confirm</span></div>'
          : "") +
        '<div class="cap"><div class="t">' +
        art.title +
        '</div><div class="c">' +
        catLabel(art.cat) +
        "</div></div>";
      card.addEventListener("click", () => {
        if (art.r18 && !r18Unlocked) {
          pendingIndex = i;
          r18Confirm.classList.add("open");
        } else {
          openLightbox(i);
        }
      });
      gridEl.appendChild(card);
    });
  }

  document.getElementById("r18Cancel").addEventListener("click", () => {
    r18Confirm.classList.remove("open");
    pendingIndex = null;
  });
  document.getElementById("r18View").addEventListener("click", () => {
    r18Unlocked = true;
    sessionStorage.setItem("r18-ok", "1");
    r18Confirm.classList.remove("open");
    if (pendingIndex !== null) openLightbox(pendingIndex);
    pendingIndex = null;
  });

  function openLightbox(i) {
    lbIndex = i;
    updateLightbox();
    lightbox.classList.add("open");
  }
  function closeLightbox() {
    lightbox.classList.remove("open");
  }
  function updateLightbox() {
    const art = currentList[lbIndex];
    lbImg.src = art.src;
    lbImg.alt = art.title;
    lbTitle.textContent = art.title;
    lbCat.textContent = catLabel(art.cat);
  }
  function step(delta) {
    lbIndex = (lbIndex + delta + currentList.length) % currentList.length;
    updateLightbox();
  }

  document.getElementById("lbClose").addEventListener("click", closeLightbox);
  document.getElementById("lbPrev").addEventListener("click", () => step(-1));
  document.getElementById("lbNext").addEventListener("click", () => step(1));
  lightbox.addEventListener("click", (e) => {
    if (e.target === lightbox) closeLightbox();
  });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && r18Confirm.classList.contains("open")) {
      r18Confirm.classList.remove("open");
      pendingIndex = null;
      return;
    }
    if (
      galleryView.hidden === false &&
      !lightbox.classList.contains("open") &&
      e.key === "Escape"
    )
      goHome();
    if (!lightbox.classList.contains("open")) return;
    if (e.key === "Escape") closeLightbox();
    if (e.key === "ArrowLeft") step(-1);
    if (e.key === "ArrowRight") step(1);
  });

  renderPortals();
})();
