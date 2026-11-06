import Foundation

/// DOM-only helpers. They never change a user agent, solve a challenge or read device data.
enum Scripts {
    static let install = """
    (() => {
      if (window.top !== window || location.hostname !== 'en.hdrama.net' || /\\/cdn-cgi\\//.test(location.pathname) || /just a moment|attention required|verify.{0,12}human/i.test(document.title) || document.querySelector('[class*="turnstile"],[id*="challenge"],iframe[src*="challenges.cloudflare.com"]')) return;
      if (window.__hdramaNativeInstalled) return;
      window.__hdramaNativeInstalled = true;
      const nativePlay = () => { location.href = 'hdrama-native://play'; };
      document.addEventListener('click', event => {
        const node = event.target instanceof Element ? event.target : null;
        const button = node && node.closest('button[aria-label="Play"]');
        if (button && /^\\/series\\/[^/]+(?:\\/episode-\\d+)?\\/?$/.test(location.pathname)) {
          event.preventDefault(); event.stopImmediatePropagation(); nativePlay();
        }
      }, true);
      const muteWebVideo = () => document.querySelectorAll('video').forEach(v => {
        v.muted = true; v.pause(); v.removeAttribute('autoplay');
        if (!v.dataset.nativePaused) {
          v.dataset.nativePaused = '1';
          v.addEventListener('play', () => { v.pause(); v.muted = true; });
        }
      });
      let pending = false;
      const observer = new MutationObserver(() => {
        if (!pending) { pending = true; requestAnimationFrame(() => { pending = false; muteWebVideo(); }); }
      });
      observer.observe(document.documentElement, {childList:true, subtree:true});
      muteWebVideo();
    })()
    """

    static let inspect = """
    JSON.stringify({url:location.href, title:document.title,
      footerHeight:(() => {
          const h=window.visualViewport?.height || innerHeight, w=window.visualViewport?.width || innerWidth;
          return Math.max(0,...Array.from(document.querySelectorAll('nav,footer,[role="navigation"],.fixed,[class*="bottom"]')).map(n => {
            const r=n.getBoundingClientRect(), s=getComputedStyle(n);
            if (s.position !== 'fixed' || r.bottom < h-4 || r.top < h*.7 || r.width < w*.7 || s.display === 'none') return 0;
            const children=Array.from(n.querySelectorAll?.('*') || []).filter(c => {
              const t=getComputedStyle(c); return t.display !== 'none' && t.visibility !== 'hidden';
            }).map(c => c.getBoundingClientRect()).filter(t => t.width > 0 && t.height > 0 && t.top >= h*.6 && t.bottom >= r.top);
            return h-Math.min(r.top,...children.map(t => t.top));
          }));
        })(), viewportHeight:window.visualViewport?.height || innerHeight,
      canonical:document.querySelector('link[rel="canonical"]')?.href || '',
      blocked:/just a moment|attention required|access denied/i.test(document.title),
      html:/^\\/series\\/[^/]+(?:\\/episode-\\d+)?\\/?$/.test(location.pathname) &&
        location.href !== __KNOWN_PAGE__ ? document.documentElement.outerHTML : ''})
    """

    static let pauseVideo = "document.querySelectorAll('video').forEach(v => { v.pause(); v.muted = true; })"

    static let observer = """
    (() => {
      if (window.__hdramaResolver) return;
      const state = window.__hdramaResolver = {sources:[], lastClick:0, attempts:0};
      const record = (raw, type) => {
        try {
          const u = new URL(raw, location.href);
          const mime = (type || '').split(';')[0].trim().toLowerCase();
          if (u.protocol !== 'https:' || u.username || u.password) return;
          if (!/\\.(m3u8|mpd|mp4|webm)$/i.test(u.pathname) &&
              !/^(application\\/(vnd\\.apple\\.mpegurl|x-mpegurl|dash\\+xml)|audio\\/(x-)?mpegurl|video\\/(mp4|webm))$/i.test(mime)) return;
          if (!state.sources.some(s => s.url === u.href)) state.sources.push({url:u.href, mimeType:mime});
          if (state.sources.length > 12) state.sources.shift();
        } catch (_) {}
      };
      if (typeof window.fetch === 'function') {
        const original = window.fetch;
        window.fetch = function(...args) {
          return original.apply(this, args).then(response => {
            if (response.ok) record(response.url, response.headers.get('content-type'));
            return response;
          });
        };
      }
      if (typeof XMLHttpRequest !== 'undefined') {
        const send = XMLHttpRequest.prototype.send;
        XMLHttpRequest.prototype.send = function(...args) {
          this.addEventListener('load', () => {
            if (this.status >= 200 && this.status < 300) record(this.responseURL, this.getResponseHeader('content-type'));
          });
          return send.apply(this, args);
        };
      }
    })()
    """

    static let resolverInspect = """
    (() => {
      if (/just a moment|attention required|access denied/i.test(document.title)) return JSON.stringify({blocked:true});
      const state = window.__hdramaResolver;
      const sources = state ? state.sources.slice() : [];
      for (const v of document.querySelectorAll('video')) {
        v.muted = true;
        for (const raw of [v.currentSrc, v.src]) {
          if (/^https:\\/\\//i.test(raw || '')) sources.push({url:raw, mimeType:''});
        }
        for (const s of v.querySelectorAll('source')) {
          if (/^https:\\/\\//i.test(s.src || '')) sources.push({url:s.src, mimeType:s.type || ''});
        }
      }
      if (typeof performance !== 'undefined' && performance.getEntriesByType) {
        for (const r of performance.getEntriesByType('resource')) {
          try { if (/\\.(m3u8|mpd|mp4|webm)$/i.test(new URL(r.name).pathname)) sources.push({url:r.name, mimeType:''}); } catch (_) {}
        }
      }
      if (!sources.length && state && (state.attempts || 0) < 3 && document.readyState !== 'loading' && Date.now() - state.lastClick >= 1800) {
        const b = document.querySelector('button[aria-label="Play"]');
        const playing = Array.from(document.querySelectorAll('video')).some(v => !v.paused);
        if (b && !playing) { state.lastClick = Date.now(); state.attempts = (state.attempts || 0) + 1; b.click(); }
      }
      return JSON.stringify({sources});
    })()
    """
}
