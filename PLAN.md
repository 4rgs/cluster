# Cluster spids-dev — estado y plan

## Fase 1 — Cluster + orquestador (master + 2 slaves)
- [x] Repo inicializado en ~/cluster
- [x] cluster.toml con routing + keywords + feedback rules
- [x] Diagnóstico real: Slave-A OK, Slave-B con modelos listados pero sin cargar
- [ ] **BLOQUEADO**: cargar qwen3.6-27b en LM Studio en 192.168.1.134 (o .197)
- [ ] clusterctl CLI (delegado a OpenCode con qwen3.6-27b una vez cargado)
- [ ] Smoke tests: routing + health + ask real

### Archivos fase 1
- `cluster.toml` — config de nodos, keywords, feedback mode
- `.stash/cluster_client_prompt.txt` — prompt atómico para OpenCode
- `bin/clusterctl` — **a construir** (CLI Python stdlib, ~300 líneas)
- `logs/ask.log` — log de cada ask (slave, model, task, latency, response preview)

## Fase 2 — Web UI para gestionar el cluster
Stack propuesto: **Astro** (liviano, estático, ya lo usás en `~/develop/landing_page`)
- Página principal: estado live de los 2 slaves (latency, model loaded, last ask)
- Form: input de task → clusterctl ask → respuesta en pantalla
- Historial: lee logs/ask.log
- Modo "verbatim vs síntesis" toggle
- Polling cada 5s para health-check
- Estilo: **neon-pixel-art** (rosa/cyan/naranja/violeta — tu theme)

### Estructura propuesta
```
~/cluster/
├── web/                          # Astro site
│   ├── src/pages/index.astro     # dashboard
│   ├── src/pages/history.astro   # log viewer
│   ├── src/components/
│   │   ├── SlaveCard.astro
│   │   ├── AskForm.astro
│   │   └── LogStream.astro
│   ├── src/styles/global.css     # neon theme
│   └── astro.config.mjs
```

### Endpoints internos que la web consume
- `clusterctl health --json` → status de slaves
- `clusterctl ask "..." --json` → respuesta
- `GET /api/logs?limit=50` → últimas N entradas de ask.log (wrapper Python)

## Decisiones de diseño
- **Routing**: keyword scoring en master. Empate → slave-b (código). Sin match → manual (te pregunto)
- **Feedback**: síntesis por default, verbatim si la task contiene "explicá técnicamente" / "análisis detallado"
- **Modelos livianos** (no saturar): gemma4:12b-mlx (chat) + qwen3.6-27b (código)
- **No filesystem write** en slaves — devuelven solo texto/código
- **Master orquesta** — vos supervisás git log + diffs

## Comandos rápidos
```bash
# Health del cluster
~/cluster/bin/clusterctl health

# Routing de prueba
~/cluster/bin/clusterctl route "explicá este código"

# Ask (post-fix LM Studio)
~/cluster/bin/clusterctl ask "agregá validación al script"

# Tail del log
tail -f ~/cluster/logs/ask.log
```
