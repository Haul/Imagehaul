import asynchttpserver, asyncnet, asyncdispatch, db_postgres, sequtils, strutils, re

type
  Haul = object
    id: int
    userid: int
    filename: string
    hash: string
    caption: string
    filesize: int
    fileext: string
    width: int
    height: int
    deleted_at: int
    created_at: int

var db {.threadvar.}: DbConn

proc fetchHaulById(id: string): Haul =
  let row = db.getRow(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null AND id=? LIMIT 1", id)
  result = Haul(
    id: parseInt(row[0]),
    filename: row[1],
    caption: row[2],
    fileext: row[3],
    created_at: parseInt(row[4])
  )

proc fetchRandomHaul(): Haul =
  let row = db.getRow(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null ORDER BY random() LIMIT 1")
  result = Haul(
    id: parseInt(row[0]),
    filename: row[1],
    caption: row[2],
    fileext: row[3],
    created_at: parseInt(row[4])
  )

proc fetchRandomHauls(c: int): seq[Haul] =
  for row in db.rows(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null ORDER BY random() LIMIT ?", c):
    result.add Haul(
      id: parseInt(row[0]),
      filename: row[1],
      caption: row[2],
      fileext: row[3],
      created_at: parseInt(row[4])
    )

proc parseHaulId(input: string, reg: Regex): string =
  var results: seq[string]
  if match(input, reg, results, 1):
    return results[0]

proc httpHandler(req: Request) {.async,gcsafe.} =
  let p = req.url.path
  if p == "/": # show homepage
    await req.respond(Http200, $fetchRandomHauls(25))

  if p == "/random": # redirect to random haul
    await req.respond(Http200, $fetchRandomHaul())

  let haulid = p.parseHaulId(re"/([0-9]+)")
  if haulid.len > 0: # show haul via id
    await req.respond(Http200, $fetchHaulById(haulid))

  # show homepage
  await req.respond(Http200, $fetchRandomHauls(25))


# main
db = open("localhost", "postgres", "", "ih")
# db.exec(sql"""CREATE TABLE hauls (
#                 id serial primary key,
#                 user_id integer,
#                 filename varchar(128),
#                 hash varchar(64),
#                 caption varchar(200),
#                 filesize integer,
#                 fileext varchar(16),
#                 width integer,
#                 height integer,
#                 deleted_at integer,
#                 created_at integer)
#                 """)

var server = newAsyncHttpServer()
waitFor server.serve(Port(6000), httpHandler)
