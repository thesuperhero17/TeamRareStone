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
  const lbXLink = document.getElementById("lbXLink");
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
      if (cat.bannerWide) {
        btn.style.setProperty("--img-wide", "url(" + cat.bannerWide + ")");
      }
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
    if (activeCat === "all") {
      // Artworks with a real recorded add-date go first, newest first.
      // Older artworks predating that tracking have no date -- keep them
      // in the existing category-grouped order, after the dated ones.
      const dated = ARTWORKS.filter((a) => a.addedDate).sort((a, b) =>
        b.addedDate.localeCompare(a.addedDate)
      );
      const undated = ARTWORKS.filter((a) => !a.addedDate);
      currentList = dated.concat(undated);
    } else {
      currentList = ARTWORKS.filter((a) => a.cat === activeCat);
    }

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
    // openLightbox() works whether the lightbox is already open (stepping
    // prev/next onto an R-18 image) or not (first open from the grid) --
    // re-adding the "open" class when it's already there is a no-op.
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
    if (art.xLink) {
      lbXLink.href = art.xLink;
      lbXLink.style.display = "flex";
    } else {
      lbXLink.removeAttribute("href");
      lbXLink.style.display = "none";
    }
  }
  function step(delta) {
    const nextIndex = (lbIndex + delta + currentList.length) % currentList.length;
    const art = currentList[nextIndex];
    if (art.r18 && !r18Unlocked) {
      // Same gate as clicking an R-18 card from the grid: pause here and
      // show the confirm dialog instead of advancing straight into it.
      // Cancelling just closes the dialog -- lbIndex never changed, so the
      // lightbox is left exactly where it was.
      pendingIndex = nextIndex;
      r18Confirm.classList.add("open");
      return;
    }
    lbIndex = nextIndex;
    updateLightbox();
  }

  document.getElementById("lbClose").addEventListener("click", closeLightbox);
  document.getElementById("lbPrev").addEventListener("click", () => step(-1));
  document.getElementById("lbNext").addEventListener("click", () => step(1));
  lightbox.addEventListener("click", (e) => {
    if (e.target === lightbox) closeLightbox();
  });

  // Swipe left/right to step through images (mobile). Works alongside the
  // side buttons, doesn't replace them. A real swipe calls preventDefault()
  // on touchend so mobile browsers don't also fire their usual synthetic
  // click afterward -- otherwise a swipe that ends over the background could
  // both advance the image AND close the lightbox in the same gesture.
  let touchStartX = null;
  let touchStartY = null;
  lightbox.addEventListener(
    "touchstart",
    (e) => {
      if (e.touches.length !== 1) { touchStartX = null; return; } // ignore pinch etc.
      touchStartX = e.touches[0].clientX;
      touchStartY = e.touches[0].clientY;
    },
    { passive: true }
  );
  lightbox.addEventListener(
    "touchend",
    (e) => {
      if (touchStartX === null) return;
      const t = e.changedTouches[0];
      const dx = t.clientX - touchStartX;
      const dy = t.clientY - touchStartY;
      touchStartX = touchStartY = null;
      const SWIPE_THRESHOLD = 50;
      if (Math.abs(dx) > SWIPE_THRESHOLD && Math.abs(dx) > Math.abs(dy) * 1.5) {
        e.preventDefault();
        step(dx < 0 ? 1 : -1); // swipe left -> next, swipe right -> prev
      }
    },
    { passive: false }
  );
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

  const toTopBtn = document.getElementById("toTop");
  function updateToTop() {
    toTopBtn.classList.toggle("show", window.scrollY > 400);
  }
  window.addEventListener("scroll", updateToTop, { passive: true });
  toTopBtn.addEventListener("click", () => {
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    window.scrollTo({ top: 0, behavior: reduceMotion ? "auto" : "smooth" });
  });
  updateToTop();
})();
