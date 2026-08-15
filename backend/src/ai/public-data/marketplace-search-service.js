const marketplaceDefinitions = Object.freeze([
  {
    id: 'yandex_market',
    name: 'Яндекс Маркет',
    buildUrl: (query) =>
      `https://market.yandex.ru/search?text=${encodeURIComponent(query)}`,
  },
  {
    id: 'ozon',
    name: 'Ozon',
    buildUrl: (query) =>
      `https://www.ozon.ru/search/?text=${encodeURIComponent(query)}`,
  },
  {
    id: 'wildberries',
    name: 'Wildberries',
    buildUrl: (query) =>
      `https://www.wildberries.ru/catalog/0/search.aspx?search=${encodeURIComponent(query)}`,
  },
]);

const decodeHtml = (value) => String(value || '')
  .replaceAll('&quot;', '"')
  .replaceAll('&#34;', '"')
  .replaceAll('&amp;', '&')
  .replaceAll('&lt;', '<')
  .replaceAll('&gt;', '>')
  .replaceAll('&#39;', "'");

const collectProducts = (value, target) => {
  if (Array.isArray(value)) {
    value.forEach((item) => collectProducts(item, target));
    return;
  }
  if (!value || typeof value !== 'object') return;
  const types = Array.isArray(value['@type']) ? value['@type'] : [value['@type']];
  if (types.includes('Product') && value.name) {
    const offer = Array.isArray(value.offers) ? value.offers[0] : value.offers;
    target.push({
      name: String(value.name).slice(0, 240),
      price: offer?.price == null ? null : String(offer.price),
      currency: offer?.priceCurrency ? String(offer.priceCurrency) : null,
      url: value.url || offer?.url || null,
    });
  }
  Object.values(value).forEach((item) => collectProducts(item, target));
};

const productsFromHtml = (html, pageUrl) => {
  const products = [];
  const scripts = String(html).matchAll(
    /<script[^>]+type=["']application\/ld\+json["'][^>]*>([\s\S]*?)<\/script>/giu,
  );
  for (const match of scripts) {
    try {
      collectProducts(JSON.parse(decodeHtml(match[1]).trim()), products);
    } catch (_) {}
  }
  return products.slice(0, 6).map((product) => {
    let url = product.url;
    try {
      if (url) {
        const page = new URL(pageUrl);
        const resolved = new URL(url, page);
        const rootDomain = page.hostname.split('.').slice(-2).join('.');
        url = resolved.hostname === rootDomain ||
            resolved.hostname.endsWith(`.${rootDomain}`)
          ? resolved.toString()
          : null;
      }
    } catch (_) {
      url = null;
    }
    return { ...product, url };
  });
};

export const searchMarketplaces = async (
  rawQuery,
  { fetchImpl = fetch, timeoutMs = 8000 } = {},
) => {
  const query = String(rawQuery || '').replace(/\s+/gu, ' ').trim().slice(0, 160);
  if (query.length < 2) return { error: 'QUERY_REQUIRED', results: [] };

  const sources = await Promise.all(marketplaceDefinitions.map(async (marketplace) => {
    const searchUrl = marketplace.buildUrl(query);
    try {
      const response = await fetchImpl(searchUrl, {
        redirect: 'follow',
        headers: {
          Accept: 'text/html,application/xhtml+xml',
          'Accept-Language': 'ru-RU,ru;q=0.9',
          'User-Agent': 'SmartHouse-Assistant/1.0',
        },
        signal: AbortSignal.timeout(timeoutMs),
      });
      const finalUrl = response.url || searchUrl;
      const html = await response.text();
      const blocked = !response.ok || /showcaptcha|captcha|access denied|robot check/iu
        .test(`${finalUrl}\n${html.slice(0, 20000)}`);
      const products = blocked ? [] : productsFromHtml(html, searchUrl);
      return {
        marketplace: marketplace.name,
        search_url: searchUrl,
        status: blocked
          ? 'browser_required'
          : products.length
            ? 'ok'
            : 'no_structured_results',
        products,
      };
    } catch (_) {
      return {
        marketplace: marketplace.name,
        search_url: searchUrl,
        status: 'browser_required',
        products: [],
      };
    }
  }));

  return {
    query,
    checked_at: new Date().toISOString(),
    sources,
    results: sources.flatMap((source) => source.products.map((product) => ({
      ...product,
      marketplace: source.marketplace,
    }))).slice(0, 12),
    note: 'Цены и наличие считаются подтверждёнными только для карточек из results. search_url предназначены для открытия пользователем.',
  };
};
