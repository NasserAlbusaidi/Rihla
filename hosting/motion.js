/* Scroll-reveal companion to _styles.css motion block. Applies .reveal only
   below the fold (no above-fold blink), removes both classes after the
   transition so component transitions regain control. No-JS and
   prefers-reduced-motion render everything static and visible. */
(function () {
  if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;
  if (!('IntersectionObserver' in window)) return;
  var els = document.querySelectorAll('.ucard, .nrow, .sec-head, .quote');
  var io = new IntersectionObserver(function (entries) {
    entries.forEach(function (en) {
      if (!en.isIntersecting) return;
      var el = en.target;
      io.unobserve(el);
      el.addEventListener('transitionend', function done() {
        el.classList.remove('reveal', 'in');
        el.removeEventListener('transitionend', done);
      });
      el.classList.add('in');
    });
  }, { rootMargin: '0px 0px -10% 0px' });
  els.forEach(function (el) {
    if (el.getBoundingClientRect().top < window.innerHeight) return;
    el.classList.add('reveal');
    io.observe(el);
  });
})();
