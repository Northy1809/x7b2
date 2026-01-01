// Owned "Lens": a photo of a product -> its brand, product and the company
// behind it, read by a vision model on Cloudflare Workers AI (free daily
// allowance, no API key: the AI binding belongs to the account).
//
// POST /id   body: JPEG (<= 1.5 MB)   ->  {brand, product, company, barcode, model, ms}
// Only what is printed on the pack: the model's own idea of a brand's owner
// was wrong too often (Sanex -> Unilever, Santa Maria -> Orkla), 25/11.
// GET  /     -> "ok"

const MODELS = {
  scout: "@cf/meta/llama-4-scout-17b-16e-instruct",
  gemma: "@cf/google/gemma-3-12b-it",
  mistral: "@cf/mistralai/mistral-small-3.1-24b-instruct",
};
const DEFAULT = "scout";
const PROMPT = `You see a photo of a product (food, drink, cosmetics, household).
Read the pack and answer with JSON only, no other text:
{"brand": "...", "product": "...", "company": "...", "barcode": "..."}
- brand: the brand name as printed on the pack (usually the logo, the biggest name). Never a product type ("Tortilla", "Parmesan"), a quantity ("8x"), a certification or claim ("Bio", "Økologisk", "Organic", "Vegan"), a protected name ("Parmigiano Reggiano", "Feta PDO") or a slogan. If the only name is a supermarket's own label, give that label's name (e.g. "Milbona", "K-Classic", "Salling").
- product: what it is, short (e.g. "hazelnut spread 400 g").
- company: the company printed on the label (e.g. after "Manufactured by", "Fabriqué par", "Hergestellt für", "Produceret for"), or "" if none is visible.
- barcode: the digits printed under a barcode if readable, else "".
Only write what is printed on the pack. Use "" for anything you cannot see.`;

function b64(bytes) {
  let s = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    s += String.fromCharCode.apply(null, bytes.subarray(i, i + chunk));
  }
  return btoa(s);
}

function parse(text) {
  if (typeof text !== "string") {
    return text && typeof text === "object" ? text : {};
  }
  const m = text.match(/\{[\s\S]*\}/);
  if (!m) return {};
  try {
    return JSON.parse(m[0]);
  } catch {
    return {};
  }
}

const clean = (v) => (typeof v === "string" ? v.trim().slice(0, 120) : "");

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (request.method === "GET") {
      return new Response("ok");
    }
    if (request.method !== "POST" || url.pathname !== "/id") {
      return new Response("not found", { status: 404 });
    }
    const bytes = new Uint8Array(await request.arrayBuffer());
    if (bytes.length < 1000 || bytes.length > 1_500_000) {
      return Response.json({ error: "size" }, { status: 400 });
    }
    const key = MODELS[url.searchParams.get("m")] ? url.searchParams.get("m") : DEFAULT;
    const started = Date.now();
    try {
      const out = await env.AI.run(MODELS[key], {
        messages: [
          {
            role: "user",
            content: [
              { type: "text", text: PROMPT },
              { type: "image_url", image_url: { url: `data:image/jpeg;base64,${b64(bytes)}` } },
            ],
          },
        ],
        max_tokens: 200,
        temperature: 0,
      });
      const j = parse(out?.response ?? out?.choices?.[0]?.message?.content ?? out);
      return Response.json({
        brand: clean(j.brand),
        product: clean(j.product),
        company: clean(j.company),
        barcode: clean(j.barcode).replace(/\D/g, ""),
        model: key,
        ms: Date.now() - started,
      });
    } catch (e) {
      return Response.json({ error: String(e).slice(0, 300), model: key }, { status: 502 });
    }
  },
};
