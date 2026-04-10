// Copypasto Marketing Site

(function () {
  "use strict";

  // --- Mobile menu toggle ---
  const toggle = document.querySelector(".nav-toggle");
  const mobileMenu = document.querySelector(".mobile-menu");

  if (toggle && mobileMenu) {
    toggle.addEventListener("click", function () {
      const expanded = toggle.getAttribute("aria-expanded") === "true";
      toggle.setAttribute("aria-expanded", String(!expanded));
      mobileMenu.hidden = expanded;
    });

    // Close menu on link click
    mobileMenu.querySelectorAll("a").forEach(function (link) {
      link.addEventListener("click", function () {
        toggle.setAttribute("aria-expanded", "false");
        mobileMenu.hidden = true;
      });
    });
  }

  // --- Smooth scroll for anchor links (fallback for older browsers) ---
  document.querySelectorAll('a[href^="#"]').forEach(function (link) {
    link.addEventListener("click", function (e) {
      var targetId = this.getAttribute("href").slice(1);
      var target = document.getElementById(targetId);
      if (target) {
        e.preventDefault();
        target.scrollIntoView({ behavior: "smooth", block: "start" });
        // Update URL without jump
        history.pushState(null, "", "#" + targetId);
      }
    });
  });

  // --- Nav background on scroll ---
  var nav = document.querySelector(".nav");
  if (nav) {
    var updateNav = function () {
      if (window.scrollY > 10) {
        nav.style.borderBottomColor = "var(--color-border)";
      } else {
        nav.style.borderBottomColor = "var(--color-border-light)";
      }
    };
    window.addEventListener("scroll", updateNav, { passive: true });
    updateNav();
  }

  // --- Waitlist form ---
  var form = document.getElementById("waitlist-form");
  var success = document.getElementById("waitlist-success");

  if (form && success) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();

      var email = form.querySelector('input[type="email"]').value;
      if (!email) return;

      // For now, just show success state.
      // Replace with actual API call when backend endpoint exists.
      // Example:
      // fetch("https://api.copypasto.com/api/waitlist", {
      //   method: "POST",
      //   headers: { "Content-Type": "application/json" },
      //   body: JSON.stringify({ email: email })
      // });

      form.hidden = true;
      success.hidden = false;
    });
  }
})();
