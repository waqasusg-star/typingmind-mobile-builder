package com.waqas.hdrama

/** DOM-only cleanup. It never changes a user agent, solves a challenge or reads private device data. */
object BrowserScripts {
    val install = """
        (() => {
          if (window.__hdramaNativeInstalled) return;
          window.__hdramaNativeInstalled = true;
          const style = document.createElement('style');
          style.textContent = '[data-ad],[data-ad-slot],.adsbygoogle,[id^="google_ads"],.ad-banner,.ad-container,.advertisement,.popup-ad,.ad-popup,.banner-ad,[data-ad-unit],[id^="div-gpt-ad"],.popunder{display:none!important}';
          (document.head || document.documentElement).appendChild(style);
          const nativePlay = () => { location.href = 'hdrama-native://play'; };
          document.addEventListener('click', event => {
            const node = event.target instanceof Element ? event.target : null;
            const button = node && node.closest('button[aria-label="Play"]');
            if (button && /^\/series\/[^/]+(?:\/episode-\d+)?\/?$/.test(location.pathname)) {
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
    """.trimIndent()
    val inspect = """
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
          html:/^\/series\/[^/]+(?:\/episode-\d+)?\/?$/.test(location.pathname) &&
            location.href !== __KNOWN_PAGE__ ? document.documentElement.outerHTML : ''})
    """.trimIndent()
    const val pauseVideo = "document.querySelectorAll('video').forEach(v => { v.pause(); v.muted = true; })"
}
