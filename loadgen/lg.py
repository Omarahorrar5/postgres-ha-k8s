import os, sys, time, json, psycopg

DSN = (f"host={os.environ['PGHOST']} dbname=app user={os.environ['PGUSER']} "
       f"password={os.environ['PGPASSWORD']} connect_timeout=2 "
       f"tcp_user_timeout=3000 keepalives=1 keepalives_idle=1 "
       f"keepalives_interval=1 keepalives_count=2")
LOG = "/tmp/log.jsonl"

def connect():
    c = psycopg.connect(DSN, autocommit=True)
    c.execute("SET statement_timeout = 3000")
    return c

def run():
    duration = int(os.environ.get("DURATION", "120"))
    interval = float(os.environ.get("INTERVAL", "0.02"))
    c = connect()
    c.execute("CREATE TABLE IF NOT EXISTS ledger(id bigint PRIMARY KEY, ts timestamptz)")
    c.execute("TRUNCATE ledger")
    c.close()
    open(LOG, "w").close()
    conn, seq, end = None, 0, time.time() + duration
    with open(LOG, "a") as f:
        while time.time() < end:
            seq += 1
            t0, ok, err = time.time(), False, None
            try:
                if conn is None or conn.closed:
                    conn = connect()
                conn.execute("INSERT INTO ledger(id, ts) VALUES (%s, now())", (seq,))
                ok = True
            except Exception as e:
                err = type(e).__name__
                try: conn.close()
                except Exception: pass
                conn = None
            rec = {"seq": seq, "t0": t0, "t1": time.time(), "ok": ok, "err": err}
            f.write(json.dumps(rec) + "\n"); f.flush()
            time.sleep(interval)
    print("RUN FINISHED", seq, "attempts", flush=True)

def verify():
    recs = [json.loads(l) for l in open(LOG)]
    acked = {r["seq"] for r in recs if r["ok"]}
    failed = [r for r in recs if not r["ok"]]
    conn = None
    for _ in range(60):
        try:
            conn = connect()
            break
        except Exception:
            time.sleep(2)
    present = {row[0] for row in conn.execute("SELECT id FROM ledger")}
    missing = sorted(acked - present)
    oks = [r for r in recs if r["ok"]]
    gap = max((b["t0"] - a["t1"] for a, b in zip(oks, oks[1:])), default=0)
    lat = sorted((r["t1"] - r["t0"]) * 1000 for r in oks)
    pct = lambda p: lat[min(len(lat) - 1, int(len(lat) * p))] if lat else 0
    print(f"attempts            : {len(recs)}")
    print(f"acknowledged        : {len(acked)}")
    print(f"failed requests     : {len(failed)}")
    print(f"LOST (acked, absent): {len(missing)}  {missing[:10]}")
    print(f"max write gap (s)   : {gap:.2f}   <- downtime")
    print(f"latency ms p50/p99  : {pct(0.5):.1f} / {pct(0.99):.1f}")

{"run": run, "verify": verify}[sys.argv[1]]()
