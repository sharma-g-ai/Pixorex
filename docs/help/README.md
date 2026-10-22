# SeaStock help

`help.html` is the user help for the 8-screen web portal: every screen, its parts and its
pop-ups, with numbered boxes on real screenshots. Open it in a browser (the pictures are in `img/`).

## Updating it after a screen changes

1. Start the web app: `cd web && npm run dev` (port 5181).
2. Retake the screenshots (uses the Chrome installed on the machine, nothing to install):
   `node docs/help/take.mjs docs/help/img`
   - `steps.mjs` lists each screenshot: which page, as which user, what to click, and which parts get a numbered box.
   - The positions of the boxes are saved in `img/shots.json`.
3. Rebuild the page: `cd docs/help && python build.py`
   - `content.py` holds the explanations. Each screenshot needs one explanation per box, in the same order; the build stops and says which screenshot is out of step.

Screenshots use the sample data, so no real customer data appears in the help.
