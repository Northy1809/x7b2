# owned-lens

Cloudflare Worker: photo of a pack -> brand, product, company and barcode digits
as printed, read by Llama 4 Scout on Workers AI (free daily allowance, no API key).
The app (lib/services/lens_client.dart) asks it only when no barcode was read, and
takes the owner from its offline table, never from the model.

Deploy: `npx wrangler deploy` (after `npx wrangler login`).
Test set (25/11 2026, 120 Open Food Facts products, front photos): brand right 105/120,
owner right 104/112 through the offline table, median 1.5 s.
