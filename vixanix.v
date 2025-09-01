// This is a remake of the classic game XONIX, originally by Ilan Rav & Dani Katz in 1984 (for MSDOS),
// and then recreated/ported by Orlin Shopov to Apple II in 1986. See other versions of the game
// at: https://archive.org/details/Xonix1984IlanRavAction , https://js-dos.com/xonix/
// and https://www.facebook.com/groups/5251478676/posts/10161388995313677/ .
module main

import os.asset
import gg
import rand
import time
import math.vec
import sokol.sgl

type Vec = vec.Vec2[f32]

const player_update_period_ms = 64
const balls_update_period_ms = 32
const cmax_x = 80
const cmax_y = 60
const wwidth = 800
const wheight = 600
const lheight = 30
const ball_directions = [
	Vec{-2.5, -2.5},
	Vec{-3, 3},
	Vec{4, -4},
	Vec{3, 3},
]

const cscreen = gg.black
const cspace = gg.black
const cland = gg.rgb(40, 40, 255)
const ctrail = gg.rgb(20, 20, 130)
const ccell_border = gg.rgb(20, 20, 220)
const cenemy_border = gg.rgb(210, 10, 10)
const cenemy_center = gg.yellow
const cball_border = gg.rgba(250, 30, 30, 200)
const cball_center = gg.white
const cinfo_area = gg.black
const cinfo = gg.light_gray
const cinfo_keys = gg.gray
const cplayer_border = gg.rgb(200, 200, 200)
const cplayer_center = gg.rgb(50, 50, 50)

enum Cell {
	space
	land
	trail
}

struct Player {
mut:
	pos    Vec
	dir    Vec
	newdir Vec
	lives  int = 3
	points int
	trail  []Vec
}

struct Ball {
mut:
	pos Vec
	dir Vec
}

struct App {
mut:
	cells        [cmax_y][cmax_x]Cell
	reachable    [cmax_y][cmax_x]Cell // updated during trail finalizing
	gg           &gg.Context = unsafe { nil }
	player       Player
	filled       f32
	enemies      []Ball
	balls        []Ball
	level        int = 1
	csize        Vec = Vec{1, 1}
	wsize        gg.Size
	xmax         f32
	ymax         f32
	player_timer time.StopWatch = time.new_stopwatch()
	balls_timer  time.StopWatch = time.new_stopwatch()
	// images:
	ienemy  gg.Image
	iball   gg.Image
	iland   gg.Image
	iwater  gg.Image
	iplayer gg.Image
}

fn main() {
	mut app := &App{}
	app.reset()
	app.gg = gg.new_context(
		bg_color:      gg.black
		width:         wwidth
		height:        wheight + lheight
		create_window: true
		window_title:  'Vixanix'
		init_fn:       init_fn
		frame_fn:      frame
		user_data:     app
		event_fn:      event
		sample_count:  2
	)
	app.gg.run()
}

fn init_fn(mut app App) {
	app.ienemy = app.gg.create_image(asset.get_path('resources/', 'enemy.png')) or { panic(err) }
	app.iball = app.gg.create_image(asset.get_path('resources/', 'ball.png')) or { panic(err) }
	app.iland = app.gg.create_image(asset.get_path('resources/', 'land.png')) or { panic(err) }
	app.iwater = app.gg.create_image(asset.get_path('resources/', 'water.png')) or { panic(err) }
	app.iplayer = app.gg.create_image(asset.get_path('resources/', 'player.png')) or { panic(err) }
}

fn (mut app App) reset() {
	app.player.lives = 3
	app.player.points = 0
	app.restart_level()
}

fn (mut app App) restart_level() {
	app.enemies.clear()
	app.player.trail.clear()
	app.balls.clear()
	app.csize = Vec{wwidth / cmax_x, wheight / cmax_y}
	app.xmax = cmax_x * app.csize.x
	app.ymax = cmax_y * app.csize.y
	app.player.pos = Vec{cmax_x / 2, 1}
	app.enemies << Ball{
		pos: Vec{cmax_x / 2 + 1, cmax_y - 2} * app.csize
		dir: Vec{3, 3}
	}
	app.enemies << Ball{
		pos: Vec{cmax_x / 2 - 1, cmax_y - 1} * app.csize
		dir: Vec{-3, -3}
	}
	for y in 0 .. cmax_y {
		for x in 0 .. cmax_x {
			app.cells[y][x] = .space
			if x in [0, 1, cmax_x - 1, cmax_x - 2] || y in [0, 1, cmax_y - 1, cmax_y - 2] {
				app.cells[y][x] = .land
			}
		}
	}
	for _ in 0 .. 1 + app.level * 2 {
		for {
			px := flimit(3, rand.f32n(cmax_x) or { 0 }, cmax_x - 6)
			py := flimit(3, rand.f32n(cmax_y) or { 0 }, cmax_y - 6)
			pos := Vec{px, py} * app.csize
			if app.fcell(pos) == .space {
				app.balls << Ball{
					pos: pos
					dir: ball_directions[rand.intn(4) or { 0 }]
				}
			}
			break
		}
	}
	app.refresh_area()
}

@[inline]
fn (app &App) fy(y f32) int {
	return ilimit(0, int(y / app.csize.y), cmax_y - 1)
}

@[inline]
fn (app &App) fx(x f32) int {
	return ilimit(0, int(x / app.csize.x), cmax_x - 1)
}

@[inline]
fn (app &App) fcell(p Vec) Cell {
	return app.cells[app.fy(p.y)][app.fx(p.x)]
}

@[inline]
fn (app &App) icell(p Vec) Cell {
	return app.cells[int(p.y)][int(p.x)]
}

@[inline]
fn (mut app App) icell_set(p Vec, c Cell) {
	app.cells[int(p.y)][int(p.x)] = c
}

fn (mut app App) mark_reachable_from(x int, y int) {
	if app.reachable[y][x] == .space {
		app.reachable[y][x] = .trail
	}
	app.mark_adjacent(x, y - 1)
	app.mark_adjacent(x, y + 1)
	app.mark_adjacent(x - 1, y)
	app.mark_adjacent(x + 1, y)
}

fn (mut app App) mark_adjacent(x int, y int) {
	if x < 0 || x > cmax_x || y < 0 || y > cmax_y {
		return
	}
	if app.reachable[y][x] == .space {
		app.mark_reachable_from(x, y)
	}
}

@[inline]
fn ilimit(min int, x int, max int) int {
	return int_max(min, int_min(x, max - 1))
}

@[inline]
fn flimit(min f32, x f32, max f32) f32 {
	return f32_max(min, f32_min(x, max - 1))
}

@[direct_array_access]
fn (mut app App) mball(mut b Ball, space Cell) Cell {
	mut npos := b.pos + b.dir
	npos.x = flimit(0, npos.x, app.xmax)
	npos.y = flimit(0, npos.y, app.ymax)
	ppos := npos
	ncell := app.fcell(ppos)
	if app.fcell(ppos) == space {
		b.pos = npos
		return ncell
	}
	adj_x := Vec{flimit(0, b.pos.x + b.dir.x, app.xmax), b.pos.y}
	adj_y := Vec{b.pos.x, flimit(0, b.pos.y + b.dir.y, app.ymax)}
	adj_x_obstacle := app.fcell(adj_x) != space
	adj_y_obstacle := app.fcell(adj_y) != space
	if adj_x_obstacle && adj_y_obstacle {
		b.dir *= Vec{-1, -1}
		return ncell
	} else if adj_x_obstacle {
		b.dir.x *= -1
		b.pos.y = npos.y
		return ncell
	} else if adj_y_obstacle {
		b.dir.y *= -1
		b.pos.x = npos.x
		return ncell
	}
	b.pos = npos
	return ncell
}

fn (mut app App) move_player() {
	opos := app.player.pos
	app.player.dir = app.player.newdir
	npos := app.player.pos + app.player.dir
	app.player.pos.x = flimit(0, npos.x, cmax_x)
	app.player.pos.y = flimit(0, npos.y, cmax_y)
	if app.icell(app.player.pos) == .space {
		app.icell_set(app.player.pos, .trail)
		app.player.trail << app.player.pos
	}
	if app.icell(opos) == .trail && app.icell(app.player.pos) == .land {
		oc := app.refresh_area()
		for pos in app.player.trail {
			app.icell_set(pos, .land)
		}
		app.fill_trailed_zone()
		app.player.trail.clear()
		nc := app.refresh_area()
		app.player.points += (nc - oc)
		if app.filled > 75.0 {
			app.next_level()
		}
	}
}

fn (mut app App) fill_trailed_zone() {
	// first, mark every space still reachable from an existing ball:
	app.reachable = app.cells
	for b in app.balls {
		app.mark_reachable_from(app.fx(b.pos.x), app.fx(b.pos.y))
	}
	// the remaining space does not contain any balls, so turn it into land:
	for y in 0 .. cmax_y {
		for x in 0 .. cmax_x {
			if app.reachable[y][x] == .space {
				app.cells[y][x] = .land
			}
		}
	}
}

fn (mut app App) next_level() {
	app.level++
	app.player.lives += 3
	app.restart_level()
}

fn (mut app App) refresh_area() int {
	mut c := 0
	for y in 0 .. cmax_y {
		for x in 0 .. cmax_x {
			if app.cells[y][x] == .land {
				c++
			}
		}
	}
	app.filled = f32(100 * c) / f32(cmax_y * cmax_x)
	return c
}

fn (mut app App) kill_player() {
	app.player.lives = int_max(0, app.player.lives - 1)
	app.player.pos = Vec{cmax_x / 2, 1}
	app.player.dir = Vec{0, 0}
	app.player.newdir = Vec{0, 0}
	for pos in app.player.trail {
		app.icell_set(pos, .space)
	}
	app.player.trail.clear()
	if app.player.lives == 0 {
		println('Game Over, points: ${app.player.points}, level: ${app.level}')
		app.level = 1
		app.reset()
	}
}

fn (mut app App) move_balls() {
	for mut b in app.balls {
		if app.mball(mut b, .space) == .trail {
			app.kill_player()
		}
	}
}

fn (mut app App) move_enemies() {
	for mut e in app.enemies {
		app.mball(mut e, .land)
		if app.fy(e.pos.y) == int(app.player.pos.y) && app.fx(e.pos.x) == int(app.player.pos.x) {
			app.kill_player()
		}
		if e.pos.y > app.ymax - 5 || e.pos.y < 2 {
			e.dir.y *= -1
		}
		if e.pos.x > app.xmax - 5 || e.pos.x < 2 {
			e.dir.x *= -1
		}
	}
}

fn event(e &gg.Event, mut app App) {
	if e.typ == .resized {
		return
	}
	if e.typ != .key_down {
		return
	}
	if e.key_code == .escape {
		app.gg.quit()
	}
	if e.key_code == .r {
		app.restart_level()
	}
	app.player.newdir = match e.key_code {
		.left { Vec{-1, 0} }
		.right { Vec{1, 0} }
		.up { Vec{0, -1} }
		.down { Vec{0, 1} }
		.space { Vec{0, 0} }
		else { Vec{0, 0} }
	}
}

fn frame(mut app App) {
	app.gg.begin()
	ws := gg.window_size()
	app.wsize = ws
	sgl.push_matrix()
	{
		sx, sy := f32(ws.width) / f32(wwidth), f32(ws.height - lheight) / f32(wheight)
		sgl.scale(sx, sy, 0)
		if app.balls_timer.elapsed().milliseconds() > balls_update_period_ms {
			app.balls_timer.restart()
			app.move_balls()
			app.move_enemies()
		}
		if app.player_timer.elapsed().milliseconds() > player_update_period_ms {
			app.player_timer.restart()
			app.move_player()
		}
		app.draw_grid()
		app.draw_balls()
		app.draw_player()
		app.draw_enemies()
	}
	sgl.pop_matrix()
	app.draw_labels()
	app.gg.end()
}

fn (mut app App) draw_text(x int, s string, color gg.Color) {
	app.gg.draw_text(x, app.wsize.height - lheight + 6, s,
		color: color
		size:  20
	)
}

fn (mut app App) draw_labels() {
	app.gg.draw_rect_filled(0, app.wsize.height - lheight, app.wsize.width, lheight, cinfo_area)
	app.draw_text(5, 'Points: ${app.player.points:06}', cinfo)
	app.draw_text(143, 'Land: ${app.filled:02.0f}%', cinfo)
	app.draw_text(250, 'Lives: ${app.player.lives:02}', cinfo)
	app.draw_text(340, 'Level: ${app.level:02}', cinfo)
	app.draw_text(app.wsize.width - 280, 'Controls: arrows, space, escape', cinfo_keys)
}

@[direct_array_access]
fn (mut app App) draw_cell(x int, y int) {
	if x < 0 || y < 0 || x > cmax_x || y > cmax_y {
		return
	}
	cy, cx := y * app.csize.y, x * app.csize.x
	match app.cells[y][x] {
		.space {
			app.gg.draw_image(cx, cy, app.csize.x, app.csize.y, app.iwater)
		}
		.land {
			app.gg.draw_image(cx, cy, app.csize.x, app.csize.y, app.iland)
		}
		.trail {
			app.gg.draw_rect_filled(cx, cy, app.csize.x, app.csize.y, ctrail)
		}
	}
}

@[direct_array_access]
fn (mut app App) draw_grid() {
	for y in 0 .. cmax_y {
		for x in 0 .. cmax_x {
			app.draw_cell(x, y)
		}
	}
}

fn (mut app App) draw_player() {
	app.gg.draw_image(app.player.pos.x * app.csize.x, app.player.pos.y * app.csize.y,
		app.csize.x, app.csize.y, app.iplayer)
}

fn (mut app App) draw_enemies() {
	radius := app.csize.x / 2
	for e in app.enemies {
		cx, cy := e.pos.x - radius, e.pos.y - radius
		app.gg.draw_image(cx, cy, app.csize.x, app.csize.y, app.ienemy)
	}
}

fn (mut app App) draw_balls() {
	radius := app.csize.x / 2
	for b in app.balls {
		cx, cy := b.pos.x + radius - 8, b.pos.y + radius - 9
		app.gg.draw_image(cx, cy, app.csize.x, app.csize.y, app.iball)
	}
}
