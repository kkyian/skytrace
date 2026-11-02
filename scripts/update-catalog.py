#!/usr/bin/env python3
"""Download the upstream aircraft catalog and build an indexed, offline SQLite snapshot."""
import csv
import datetime
import gzip
import io
import pathlib
import sqlite3
import urllib.request

source = 'https://raw.githubusercontent.com/wiedehopf/tar1090-db/csv/aircraft.csv.gz'
target = pathlib.Path(__file__).resolve().parent.parent / 'Sources/Skytrace/Resources/catalog.sqlite'
with urllib.request.urlopen(source, timeout=90) as response:
    compressed = response.read()
target.parent.mkdir(parents=True, exist_ok=True)
temporary = target.with_suffix('.sqlite.new')
if temporary.exists():
    temporary.unlink()
connection = sqlite3.connect(temporary)
try:
    connection.execute('CREATE TABLE aircraft(hex TEXT PRIMARY KEY,registration TEXT,type TEXT,flags TEXT,description TEXT,year TEXT,owner TEXT)')
    with gzip.GzipFile(fileobj=io.BytesIO(compressed)) as archive:
        rows = csv.reader(io.TextIOWrapper(archive, encoding='utf-8'), delimiter=';')
        connection.executemany('INSERT OR REPLACE INTO aircraft VALUES(?,?,?,?,?,?,?)', ((r + [''] * 7)[:7] for r in rows if len(r) > 2))
    count = connection.execute('SELECT COUNT(*) FROM aircraft').fetchone()[0]
    if count < 500000:
        raise ValueError(f'Unexpected catalog size: {count}. Existing catalog has been preserved.')
    connection.executescript('CREATE INDEX registration_idx ON aircraft(registration COLLATE NOCASE); CREATE INDEX type_idx ON aircraft(type COLLATE NOCASE); CREATE TABLE metadata(key TEXT PRIMARY KEY,value TEXT);')
    connection.executemany('INSERT INTO metadata VALUES(?,?)', [('source', 'Mictronics / tar1090-db'), ('downloaded', datetime.date.today().isoformat()), ('url', 'https://github.com/wiedehopf/tar1090-db')])
    connection.commit()
finally:
    connection.close()
temporary.replace(target)
print(f'Updated {count:,} records. Run scripts/build-app.sh to rebuild Skytrace.app.')
