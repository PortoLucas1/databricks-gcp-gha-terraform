# Published deliverables

The lab's deliverables as pages, built from the markdown in this repository. Standalone HTML: open them in a browser, or serve this folder (for example with GitHub Pages).

| Page | Built from |
|---|---|
| [`index.html`](index.html): the deliverables, E1–E7, with the architecture and authentication diagrams | [`docs/deliverables/`](../deliverables/) |
| [`status.html`](status.html): the Entra ID test status, a one-page summary for sharing | [`status.md`](status.md) |
| [`aim-assessment.html`](aim-assessment.html): an Entra identity for the pipeline, provisioned by AIM | [`docs/AIM_ENTRA_ASSESSMENT.md`](../AIM_ENTRA_ASSESSMENT.md) |

Rebuild after changing any of the sources, and commit the pages with them:

```bash
python docs/site/build.py
```

`build.py` converts the markdown (a small subset: headings, paragraphs, tables, lists, code, links), draws the two diagrams as inline SVG, and wraps each page in `template.html`'s styles. Links to the repository's markdown files become plain text, since a page may be read away from the repository. The assessment's diagram is Mermaid, rendered by a pinned script from jsDelivr.
