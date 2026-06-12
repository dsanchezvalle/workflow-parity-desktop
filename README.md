# Acme — static site fixture

A minimal static marketing site (a homepage plus an about page) used as a
throwaway fixture for the workflow-template **twin-repo parity test**
(see issue dsanchezvalle/workflow-template#67).

The site is intentionally tiny so that issues exercise the **workflow**
(issue → analyze → start → review → PR), not the implementation.

## Structure

```
src/
  index.html   # homepage (hero, features, footer)
  about.html   # about page
  styles.css   # shared styles
```

## Local preview

No build step. Open `src/index.html` in a browser, or serve the folder:

```bash
npx serve src
```

## Scripts

`npm` scripts are intentionally trivial (this is a fixture, not a real
product): `lint`, `typecheck`, `build`, and `test` are no-ops kept green
so CI exercises the workflow end-to-end.
