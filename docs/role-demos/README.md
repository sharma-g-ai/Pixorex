# Role demos

The working web portal published as one page per role, each starting signed in:

| Role | Signed in as | Page |
|---|---|---|
| PPG Admin (all customers) | Dana Whitfield (`u01`) | https://claude.ai/artifact/PL5W2BGmGL6fzVoSD92aUh |
| Customer Admin | Ingrid Solberg, Nordhavn (`u06`) | https://claude.ai/artifact/U5mb4zXPKuHrmKqp2bSUK1 |
| Ship Admin | Erik Lund, Nordhavn Aurora (`u12`) | https://claude.ai/artifact/LZ1U7ohgYoECJMMcXDgAz8 |

## Rebuilding after a change

    cd web
    VITE_DEMO_USER=u01 npx vite build --outDir ../docs/role-demos/dist-u01 --emptyOutDir
    VITE_DEMO_USER=u06 npx vite build --outDir ../docs/role-demos/dist-u06 --emptyOutDir
    VITE_DEMO_USER=u12 npx vite build --outDir ../docs/role-demos/dist-u12 --emptyOutDir
    cd ../docs/role-demos && python pack.py

`pack.py` writes `ppg-admin.html`, `customer-admin.html` and `ship-admin.html` (the app in one
file each). Republish each to its page above. `VITE_DEMO_USER` makes the build start signed in
as that sample user and keep its navigation inside the page; without it the app is unchanged.
