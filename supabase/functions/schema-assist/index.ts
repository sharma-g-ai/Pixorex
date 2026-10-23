const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

type SchemaAssistRequest = {
  image_data_url?: string;
  image_data_urls?: string[];
  model?: string;
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function cleanJsonText(text: string): string {
  let cleaned = text.trim();
  if (cleaned.startsWith("```")) {
    cleaned = cleaned.replace(/^```(?:json)?\s*/i, "").trim();
    cleaned = cleaned.replace(/```$/i, "").trim();
  }
  const start = cleaned.indexOf("{");
  const end = cleaned.lastIndexOf("}");
  if (start >= 0 && end > start) {
    cleaned = cleaned.slice(start, end + 1);
  }
  return cleaned;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  const openaiApiKey = Deno.env.get("OPENAI_API_KEY");
  if (!openaiApiKey) {
    return jsonResponse({ error: "Automatic schema generation is not configured." }, 500);
  }

  let payload: SchemaAssistRequest;
  try {
    payload = await req.json();
  } catch (_) {
    return jsonResponse({ error: "Request body must be JSON." }, 400);
  }

  const imageDataUrls = Array.isArray(payload.image_data_urls)
    ? payload.image_data_urls.map((value) => String(value || "").trim()).filter(Boolean)
    : [String(payload.image_data_url || "").trim()].filter(Boolean);

  if (imageDataUrls.length === 0) {
    return jsonResponse({ error: "At least one image is required." }, 400);
  }
  if (imageDataUrls.length > 3) {
    return jsonResponse({ error: "Use up to 3 images for one schema." }, 400);
  }
  if (imageDataUrls.some((imageDataUrl) => !imageDataUrl.startsWith("data:image/"))) {
    return jsonResponse({ error: "Each image must be an image data URL." }, 400);
  }

  // 10 MB binary image is roughly 13.4 MB base64 plus the data URL prefix.
  if (imageDataUrls.some((imageDataUrl) => imageDataUrl.length > 14_500_000)) {
    return jsonResponse({ error: "One image is larger than the 10 MB limit." }, 413);
  }

  const model = String(payload.model || "gpt-4.1-mini").trim() || "gpt-4.1-mini";
  const imageCount = imageDataUrls.length;
  const imageContext = imageCount === 1
    ? "You received one image. Derive the schema from that label only."
    : `You received ${imageCount} images. Treat them as front/back/side views or examples of the same label type and derive one consolidated reusable schema using the union of fields visible across all images.`;
  const prompt = `You are designing a schema for an OCR extraction system.

${imageContext}

Look at the label, nameplate, product label, or data plate in the provided image(s). Return strict JSON with a proposed schema in this exact shape:

{
  "label_type_name": "Short human-readable name (e.g. 'Motor Nameplate')",
  "description": "One sentence describing what this label is for.",
  "fields": [
    {
      "name": "snake_case_internal_key",
      "description": "Short helpful description for the extraction model",
      "mandatory": true
    }
  ]
}

Rules:
- If multiple images are provided, build ONE schema entry for the label type, not one schema per image.
- For multiple images, inspect each image independently first, then merge the fields. Do not let a simpler front image suppress fields visible on a back/side image.
- Use high recall for schema creation: include every reusable field that is clearly visible or labeled in any provided image. A field only needs to appear in one image to belong in the schema.
- Include fields that are actually visible or clearly labeled in at least one provided image.
- Consolidate synonyms into one canonical field. Examples: lot_no/batch_no -> batch_number, mfg_date/date_of_packaging -> manufacturing_date, exp_date/use_by -> expiry_date, barcode/upc/gtin -> upc_barcode.
- Do not create image-specific fields such as image_1_field, front_text, back_text, or side_text unless those words are actual printed labels.
- Prefer the broader reusable label type when panels differ. Example: if front cover has title/author and back cover has ISBN/price/publisher, create a "Book Cover" schema with title, author, isbn, price, publisher, and other visible back-cover fields.
- If images appear to show unrelated label types, choose the dominant intended label type and mention the mismatch briefly in the description.
- Use snake_case for the name (lowercase letters, numbers, underscores).
- Do not use spaces or punctuation in field names.
- Mark a field as mandatory=true only when it is an identifier (serial, model, part number), a critical operating value (rpm, voltage, pressure), or a regulated/compliance value (temperature code, hazard class). Otherwise mandatory=false.
- Do not invent fields that are not on the provided image(s).
- Prefer stable reusable field names over exact printed label casing.
- Do not reduce the schema to only common fields shared by all images. This is not an intersection task; it is a union task.
- Return only the JSON object, no commentary, no markdown fences.`;

  const content = [
    { type: "text", text: prompt },
    ...imageDataUrls.map((url) => ({
      type: "image_url",
      image_url: { url, detail: "low" },
    })),
  ];

  const openaiResponse = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${openaiApiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        {
          role: "user",
          content,
        },
      ],
      temperature: 0,
      max_tokens: 1400,
    }),
  });

  if (!openaiResponse.ok) {
    console.error("Schema assist provider request failed", {
      status: openaiResponse.status,
      detail: (await openaiResponse.text().catch(() => "")).slice(0, 500),
    });
    return jsonResponse({ error: "Automatic schema generation failed." }, 502);
  }

  const openaiJson = await openaiResponse.json();
  const rawContent = openaiJson?.choices?.[0]?.message?.content;
  if (!rawContent || typeof rawContent !== "string") {
    return jsonResponse({ error: "Automatic schema generation returned an empty result." }, 502);
  }

  try {
    const parsed = JSON.parse(cleanJsonText(rawContent));
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return jsonResponse({ error: "Automatic schema generation returned an invalid result." }, 502);
    }
    return jsonResponse(parsed);
  } catch (_) {
    console.error("Schema assist JSON parse failed", { detail: rawContent.slice(0, 500) });
    return jsonResponse(
      {
        error: "Automatic schema generation returned an invalid result.",
      },
      502,
    );
  }
});
