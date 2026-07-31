# NetApp GSD Recipe — tech talk deck

## Generate

```bash
cd docs/presentations
python3 -m venv .venv   # first time
.venv/bin/pip install python-pptx
.venv/bin/python generate_tech_talk.py
```

Output: **`NetApp-GSD-Recipe-Tech-Talk.pptx`**

## Demo video (slide 10 — post-recipe walkthrough)

Copy your screen recording to:

```text
docs/presentations/assets/recipe-demo-post-usage.mp4
```

Then re-run `generate_tech_talk.py`. The video is embedded on the **Post-recipe walkthrough** slide (click ▶ in Presenter View).

Default source used locally:

```text
~/Downloads/GMT20260717-054238_Recording_2056x1330.mp4
```

(`assets/*.mp4` is gitignored — too large for the repo; the `.pptx` you generate locally carries the embedded media.)
