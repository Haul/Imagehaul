import asynchttpserver, asyncdispatch, db_postgres, strutils, re

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

# sql functions
proc fetchHaulById(id: string): Haul =
  let row = db.getRow(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null AND id=? LIMIT 1", id)
  if row[0].len <= 0: return
  result = Haul(
    id: parseInt(row[0]),
    filename: row[1],
    caption: row[2],
    fileext: row[3],
    created_at: parseInt(row[4])
  )

proc fetchRandomHaul(): Haul =
  let row = db.getRow(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null ORDER BY random() LIMIT 1")
  if row[0].len <= 0: return
  result = Haul(
    id: parseInt(row[0]),
    filename: row[1],
    caption: row[2],
    fileext: row[3],
    created_at: parseInt(row[4])
  )

proc fetchRandomHauls(c: int): seq[Haul] =
  for row in db.rows(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null ORDER BY random() LIMIT ?", c):
    if row[0].len <= 0: return
    result.add Haul(
      id: parseInt(row[0]),
      filename: row[1],
      caption: row[2],
      fileext: row[3],
      created_at: parseInt(row[4])
    )

proc fetchPreviousId(h: Haul): string =
  let row = db.getRow(sql"SELECT * FROM hauls WHERE deleted_at IS null AND id<? ORDER BY id DESC LIMIT 1")
  if row[0].len <= 0: return
  result = row[0]

proc fetchNextId(h: Haul): string =
  let row = db.getRow(sql"SELECT * FROM hauls WHERE deleted_at IS null AND id>? ORDER BY id ASC LIMIT 1")
  if row[0].len <= 0: return
  result = row[0]

# http functions
proc parseHaulId(input: string, reg: Regex): string =
  var results: array[1, string]
  if input.match(reg, results):
    return results[0]

proc httpHandler(req: Request) {.async,gcsafe.} =
  let p = req.url.path
  if p == "/": # show homepage
    await req.respond(Http200, $fetchRandomHauls(25))

  if p == "/random": # redirect to random haul
    await req.respond(Http200, $fetchRandomHaul())

  let haulid = p.parseHaulId(re"\/([0-9]+)")
  if haulid.len > 0: # show haul via id
    await req.respond(Http200, $fetchHaulById(haulid))

  # show homepage
  await req.respond(Http200, $fetchRandomHauls(25))


# render functions
proc haulUrl(h: Haul): string =
  "https://imagehaul.com/" & $h.id

proc thumbUrl(h: Haul): string =
  "https://imagehaul.s3-us-west-1.amazonaws.com/thethumbs/medium/" & h.filename & ".jpg"

proc imageUrl(h: Haul): string =
  "https://imagehaul.s3-us-west-1.amazonaws.com/thehauls/" & h.filename & "." & h.fileext

proc renderGridItem(h: Haul): string =
  # anchor tag
  result.add "<a href=\""
  result.add h.haulUrl()
  result.add "\" class=\"item\">"
  # img tag
  result.add "<img src=\""
  result.add h.thumbUrl()
  result.add "\">"
  # close anchor
  result.add "</a>"

proc renderHaulItem(h: Haul): string =
  # caption
  result.add "<h3>"
  result.add h.caption
  result.add "</h3>"
  # image
  result.add "<img src=\""
  result.add h.imageUrl()
  result.add "\">"

proc renderPreviousButton(h: Haul): string =
  if h.id <= 1: return
  let id = h.fetchPreviousId()
  if id.len <= 0: return
  result.add "<a href=\""
  result.add "https://imagehaul.com/" & id
  result.add "\" class=\"prev\">Prev</a>"

proc renderNextButton(h: Haul): string =
  if h.id >= 15000: return
  let id = h.fetchNextId()
  if id.len <= 0: return
  result.add "<a href=\""
  result.add "https://imagehaul.com/" & id
  result.add "\" class=\"next\">Next</a>"

let h = Haul(id: 1234, caption: "test caption please ignore", filename: "feelsfilenameman", fileext: "gif")
echo renderGridItem(h)
echo renderHaulItem(h)

# main
# db = open("localhost", "postgres", "", "ih")

# var server = newAsyncHttpServer()
# waitFor server.serve(Port(6000), httpHandler)
