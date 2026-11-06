package com.waqas.hdrama

/** Observe public media response metadata without reading bodies or changing website requests. */
object ResolverScripts {
    val observe = """
        (() => {
          if (window.__hdramaResolver) return;
          const state = window.__hdramaResolver = {sources:[], lastClick:0};
          const record = (raw, type) => {
            try {
              const u = new URL(raw, location.href);
              const mime = (type || '').split(';')[0].trim().toLowerCase();
              if (u.protocol !== 'https:' || u.username || u.password) return;
              if (!/\.(m3u8|mpd|mp4|webm)$/i.test(u.pathname) &&
                  !/^(application\/(vnd\.apple\.mpegurl|x-mpegurl|dash\+xml)|audio\/(x-)?mpegurl|video\/(mp4|webm))${'$'}/i.test(mime)) return;
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
    """.trimIndent()

    val inspect = """
        (() => {
          if (/just a moment|attention required|access denied/i.test(document.title)) return JSON.stringify({blocked:true});
          const state = window.__hdramaResolver;
          const sources = state ? state.sources.slice() : [];
          for (const v of document.querySelectorAll('video')) {
            v.muted = true;
            // HLS.js sets currentSrc to blob:; inspect src/source and response metadata too.
            for (const raw of [v.currentSrc, v.src]) {
              if (/^https:\/\//i.test(raw || '')) sources.push({url:raw, mimeType:''});
            }
            for (const s of v.querySelectorAll('source')) {
              if (/^https:\/\//i.test(s.src || '')) sources.push({url:s.src, mimeType:s.type || ''});
            }
          }
          // Include earlier filename-based resources when document-start injection is unavailable.
          if (typeof performance !== 'undefined' && performance.getEntriesByType) {
            for (const r of performance.getEntriesByType('resource')) {
              try { if (/\.(m3u8|mpd|mp4|webm)${'$'}/i.test(new URL(r.name).pathname)) sources.push({url:r.name, mimeType:''}); } catch (_) {}
            }
          }
          if (!sources.length && state && document.readyState !== 'loading' && Date.now() - state.lastClick >= 1800) {
            const b = document.querySelector('button[aria-label="Play"]');
            // Reattempt after hydration, but do not toggle a playing video back to pause.
            const playing = Array.from(document.querySelectorAll('video')).some(v => !v.paused);
            if (b && !playing) { state.lastClick = Date.now(); b.click(); }
          }
          return JSON.stringify({sources});
        })()
    """.trimIndent()
}
