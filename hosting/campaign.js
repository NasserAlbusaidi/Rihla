(function () {
  const allowedKeys = [
    'utm_source',
    'utm_medium',
    'utm_campaign',
    'utm_content',
    'utm_term',
  ];
  const currentParams = new URLSearchParams(window.location.search);
  const referrerParams = new URLSearchParams();

  allowedKeys.forEach((key) => {
    const value = currentParams.get(key);
    if (value) referrerParams.set(key, value);
  });

  if (!referrerParams.toString()) return;

  document
    .querySelectorAll('a[href*="play.google.com/store/apps/details"]')
    .forEach((link) => {
      const url = new URL(link.href);
      if (url.searchParams.get('id') !== 'com.safar.safar') return;
      if (url.searchParams.has('referrer')) return;
      url.searchParams.set('referrer', referrerParams.toString());
      link.href = url.toString();
    });

  document
    .querySelectorAll('a[data-alpha-access-mailto][href^="mailto:"]')
    .forEach((link) => {
      const url = new URL(link.href);
      if (url.protocol !== 'mailto:') return;

      const body = url.searchParams.get('body') || '';
      const decodedBody = decodeURIComponent(body);
      if (decodedBody.includes('Campaign source:')) return;

      const nextBody = `${decodedBody}\n\nCampaign source: ${referrerParams.toString()}`;
      const encodedBody = encodeURIComponent(nextBody);
      const params = new URLSearchParams(url.search.slice(1));
      params.delete('body');

      const query = params.toString();
      link.href = `${url.protocol}${url.pathname}?${query}${query ? '&' : ''}body=${encodedBody}`;
    });
})();
