import asynchttpserver, asyncdispatch, db_postgres, strutils, re, random

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
    deleted_at: string
    created_at: string

const
  RootUrl = "https://imagehaul.com/"
  MaxHaulCount = 15768

var db {.threadvar.}: DbConn


# sql functions
proc fetchHaulById(id: int): Haul =
  let row = db.getRow(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null AND id = ? LIMIT 1", id)
  if row[0].len <= 0: return
  result = Haul(
    id: parseInt(row[0]),
    filename: row[1],
    caption: row[2],
    fileext: row[3],
    created_at: row[4]
  )

proc fetchRandomHaul(): Haul =
  let row = db.getRow(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null ORDER BY random() LIMIT 1")
  if row[0].len <= 0: return
  result = Haul(
    id: parseInt(row[0]),
    filename: row[1],
    caption: row[2],
    fileext: row[3],
    created_at: row[4]
  )

proc fetchRandomHauls(c: int): seq[Haul] =
  for row in db.rows(sql"SELECT id, filename, caption, fileext, created_at FROM hauls WHERE deleted_at IS null ORDER BY random() LIMIT ?", c):
    if row[0].len <= 0: return
    result.add Haul(
      id: parseInt(row[0]),
      filename: row[1],
      caption: row[2],
      fileext: row[3],
      created_at: row[4]
    )

proc fetchPreviousId(h: Haul): string =
  let row = db.getRow(sql"SELECT id FROM hauls WHERE deleted_at IS null AND id < ? ORDER BY id DESC LIMIT 1", h.id)
  if row[0].len <= 0: return
  result = row[0]

proc fetchNextId(h: Haul): string =
  let row = db.getRow(sql"SELECT id FROM hauls WHERE deleted_at IS null AND id > ? ORDER BY id ASC LIMIT 1", h.id)
  if row[0].len <= 0: return
  result = row[0]


# render functions
proc haulUrl(h: Haul): string =
  RootUrl & $h.id

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
  result.add "<div class=\"haulitem\">"
  result.add "<h3>"
  result.add h.caption
  result.add "</h3>"
  # determine if webm or not
  if h.fileext == "webm":
    # render webm/video
    result.add "<video src=\""
    result.add h.imageUrl()
    result.add "\" onloadstart=\"this.volume=0.2\" autoplay preload loop controls>"
  else:
    # render image
    result.add "<img src=\""
    result.add h.imageUrl()
    result.add "\">"
  result.add "</div>"

proc renderPreviousButton(h: Haul): string =
  if h.id <= 1: return
  let id = h.fetchPreviousId()
  if id.len <= 0: return
  # anchor tag
  result.add "<a href=\""
  result.add RootUrl & id
  result.add "\" class=\"prev\">Prev</a>"

proc renderNextButton(h: Haul): string =
  if h.id >= MaxHaulCount: return
  let id = h.fetchNextId()
  if id.len <= 0: return
  # anchor tag
  result.add "<a href=\""
  result.add RootUrl & id
  result.add "\" class=\"next\">Next</a>"

proc renderRandomButton(): string =
  result.add "<a href=\""
  result.add RootUrl & "/"
  result.add $rand(MaxHaulCount)
  result.add "\">Random</a>"

proc renderTemplate(tmpl: string, data: tuple[nav, content: string]): string =
  result = tmpl.replace(re"\{\{nav\}\}", data.nav)
  return result.replace(re"\{\{content\}\}", data.content)

proc renderHomepage(hs: seq[Haul]): string =
  result.add "<div class=\"grid\">"
  for _, h in hs:
    result.add h.renderGridItem()
  result.add "</div>"
  renderTemplate(readFile("./index.html"), (nav: renderRandomButton(), content: result))

proc renderHaulPage(h: Haul): string =
  if h.id <= 0: return renderTemplate(readFile("./index.html"), (nav: renderRandomButton(), content: "<p>Could not find haul.</p>"))
  let nav = renderPreviousButton(h) & renderRandomButton() & renderNextButton(h)
  renderTemplate(readFile("./index.html"), (nav: nav, content: h.renderHaulItem))


# http functions
proc parseHaulId(input: string, reg: Regex): string =
  var results: array[1, string]
  if input.match(reg, results):
    return results[0]

proc httpHandler(req: Request) {.async,gcsafe.} =
  let p = req.url.path
  if p == "/": # show homepage
    await req.respond(Http200, renderHomepage(fetchRandomHauls(27)))

  if p == "/random": # redirect to random haul
    await req.respond(Http200, renderHaulPage(fetchHaulById(rand(MaxHaulCount))))

  let haulid = p.parseHaulId(re"\/([0-9]+)")
  if haulid.len > 0: # show haul via id
    await req.respond(Http200, renderHaulPage(fetchHaulById(parseInt(haulid))))

  # show homepage
  await req.respond(Http200, renderHomepage(fetchRandomHauls(27)))


# main
randomize()
db = open("localhost", "postgres", "", "ih")

var server = newAsyncHttpServer()
waitFor server.serve(Port(6001), httpHandler)
