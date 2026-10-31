#!/usr/bin/env python3
"""
Foldfleet — Python mirror of the Swift game rules (GameModel.swift / AIPlayer.swift).

Purpose: validate the RULES on Windows / Linux, where Xcode and Swift are
not available. This does NOT compile Swift and does NOT prove the Swift
files compile — that check needs Xcode 27.1 on a Mac (see README.md).

Run:  python3 scripts/verify_logic.py
Exit 0 = all rule tests passed.
"""
import random
import sys
from dataclasses import dataclass, field

GRID = 10
SHIPS = [("Carrier", 5), ("Battleship", 4), ("Cruiser", 3), ("Submarine", 3), ("Destroyer", 2)]

@dataclass(frozen=True)
class Coord:
    r: int
    c: int
    @property
    def valid(self): return 0 <= self.r < GRID and 0 <= self.c < GRID

@dataclass
class Ship:
    name: str
    length: int
    origin: Coord
    horizontal: bool
    hits: set = field(default_factory=set)
    @property
    def cells(self):
        return [Coord(self.origin.r, self.origin.c + i) if self.horizontal
                else Coord(self.origin.r + i, self.origin.c) for i in range(self.length)]
    @property
    def sunk(self): return set(self.cells) <= self.hits

class Fleet:
    def __init__(self): self.ships = []; self.shots = {}  # Coord -> bool hit
    def can_place(self, ship, ignore=None):
        if not all(c.valid for c in ship.cells): return False
        others = [s for s in self.ships if s.name != ignore]
        return not any(set(s.cells) & set(ship.cells) for s in others)
    def place(self, ship):
        if not self.can_place(ship, ignore=ship.name): return False
        self.ships = [s for s in self.ships if s.name != ship.name] + [ship]
        return True
    def ship_at(self, coord):
        return next((s for s in self.ships if coord in s.cells), None)
    @property
    def destroyed(self): return bool(self.ships) and all(s.sunk for s in self.ships)

class Game:
    def __init__(self):
        self.p1, self.p2 = Fleet(), Fleet()
        self.turn = "P1"; self.phase = "placement"; self.winner = None
    def start(self):
        assert len(self.p1.ships) == 5 and len(self.p2.ships) == 5
        self.phase = "battle"
    def fire(self, coord, shooter):
        if self.winner: return "gameOver"
        if self.phase != "battle": return "invalid"
        if shooter != self.turn: return "notYourTurn"
        if not coord.valid: return "invalid"
        target = self.p2 if shooter == "P1" else self.p1
        if coord in target.shots: return "alreadyShot"
        ship = target.ship_at(coord)
        if ship:
            ship.hits.add(coord); target.shots[coord] = True
            result = "sunk" if ship.sunk else "hit"
        else:
            target.shots[coord] = False; result = "miss"
        if target.destroyed:
            self.phase = "finished"; self.winner = shooter
        else:
            self.turn = "P2" if shooter == "P1" else "P1"
        return result

def random_fleet(rng):
    f = Fleet()
    for name, length in SHIPS:
        while True:
            horiz = rng.random() < 0.5
            max_r = GRID - 1 if horiz else GRID - length
            max_c = GRID - length if horiz else GRID - 1
            s = Ship(name, length, Coord(rng.randint(0, max_r), rng.randint(0, max_c)), horiz)
            if f.place(s): break
    return f

def ai_next(difficulty, shots, sunk_lengths, rng, sunk_shots=frozenset()):
    tried = set(shots)
    untried = [Coord(r, c) for r in range(GRID) for c in range(GRID) if Coord(r, c) not in tried]
    if not untried: return None
    hits = [c for c, h in shots.items() if h]
    active_hits = [c for c in hits if c not in sunk_shots]
    if difficulty == "easy":
        return rng.choice(untried)
    if difficulty == "normal" and active_hits:
        cand = []
        for h in active_hits:
            for d in [(-1,0),(1,0),(0,-1),(0,1)]:
                n = Coord(h.r+d[0], h.c+d[1])
                if n.valid and n not in tried: cand.append(n)
        if cand: return rng.choice(cand)
        parity = [c for c in untried if (c.r+c.c) % 2 == 0]
        return rng.choice(parity or untried)
    if difficulty == "hard":
        # probability density, same idea as Swift: score placements of afloat ships
        from collections import Counter
        counts = Counter(l for _, l in SHIPS)
        for l in sunk_lengths: counts[l] -= 1
        lengths = [l for l, n in counts.items() for _ in range(max(0, n))]
        score = {c: 0 for c in untried}
        for length in lengths:
            for r in range(GRID):
                for c in range(GRID):
                    for horiz in (True, False):
                        cells = [Coord(r, c+i) if horiz else Coord(r+i, c) for i in range(length)]
                        if not all(x.valid for x in cells): continue
                        if any(shots.get(x) is False for x in cells): continue
                        if any(x in sunk_shots for x in cells): continue
                        hit_n = sum(1 for x in cells if x in active_hits)
                        w = 1 if hit_n == 0 else 10 + hit_n*10
                        for x in cells:
                            if x not in tried: score[x] += w
        best = max(score.values())
        best_cells = [c for c, s in score.items() if s == best]
        parity = [c for c in best_cells if (c.r+c.c) % 2 == 0]
        return rng.choice(parity or best_cells)
    parity = [c for c in untried if (c.r+c.c) % 2 == 0]
    return rng.choice(parity or untried)

# --- tests ---
passed = failed = 0
def check(name, cond):
    global passed, failed
    if cond: passed += 1; print(f"  PASS {name}")
    else: failed += 1; print(f"  FAIL {name}")

rng = random.Random(42)
print("Placement")
f = Fleet()
check("valid horizontal", f.place(Ship("Carrier",5,Coord(0,0),True)))
check("valid vertical", f.place(Ship("Destroyer",2,Coord(5,5),False)))
check("overlap rejected", not f.place(Ship("Battleship",4,Coord(0,2),True)))
check("off-grid right rejected", not f.place(Ship("Carrier",5,Coord(0,7),True)))
check("off-grid bottom rejected", not f.place(Ship("Carrier",5,Coord(7,0),False)))
check("edge allowed", f.place(Ship("Cruiser",3,Coord(9,7),True)))
check("random fleets valid x50", all(
    (lambda rf: len(rf.ships)==5 and len(set(sum([s.cells for s in rf.ships],[])))==17
     and all(c.valid for s in rf.ships for c in s.cells))(random_fleet(random.Random(i)))
    for i in range(50)))

print("Battle")
g = Game(); g.p1 = random_fleet(rng); g.p2 = random_fleet(rng); g.start()
check("cannot start incomplete", (lambda gg: (gg.phase=="placement"))(Game()))
check("out of turn rejected", Game().fire(Coord(0,0),"P2") in ("invalid","notYourTurn"))
# hit/miss on known cells
enemy_cell = g.p2.ships[0].cells[0]
check("hit detected", g.fire(enemy_cell,"P1") in ("hit","sunk"))
check("turn switches", g.turn=="P2")
miss_cell = next(Coord(r, c) for r in range(10) for c in range(10)
                 if g.p1.ship_at(Coord(r, c)) is None)
check("miss detected", g.fire(miss_cell,"P2")=="miss")
check("repeat rejected", g.fire(enemy_cell,"P1")=="alreadyShot")

print("Sinking / victory")
g2 = Game()
g2.p1.ships=[Ship("Destroyer",2,Coord(0,0),True)]
g2.p2.ships=[Ship("Destroyer",2,Coord(5,5),True)]
g2.phase="battle"
check("first hit", g2.fire(Coord(5,5),"P1")=="hit")
g2.fire(Coord(0,0),"P2")
check("sunk + victory", g2.fire(Coord(5,6),"P1")=="sunk" and g2.winner=="P1" and g2.phase=="finished")
check("no shots after game over", g2.fire(Coord(1,1),"P2")=="gameOver")

print("AI")
for diff in ("easy","normal","hard"):
    shots={}
    ok=True
    for _ in range(30):
        s=ai_next(diff, shots, [], rng)
        if s is None or not s.valid or s in shots: ok=False; break
        shots[s]=False
    check(f"{diff} valid untried x30", ok)
shots={Coord(5,5):True}
adj=sum(1 for _ in range(20) if (lambda s: s and abs(s.r-5)+abs(s.c-5)==1)(ai_next("normal", shots, [], rng)))
check("normal targets adjacent to hit", adj>0)
shots={Coord(5,5):True, Coord(5,6):True}
line=sum(1 for _ in range(50) if (lambda s: s and s.r==5 and s.c in (4,7))(ai_next("hard", shots, [], rng)))
check(f"hard extends line of hits ({line}/50)", line>20)
full={Coord(r,c):False for r in range(10) for c in range(10)}
check("AI nil when board exhausted", ai_next("hard", full, [], rng) is None)
# Sunk ships must not attract shots (Swift fix, 27 Oct 2026)
sunk_shots={Coord(5,5), Coord(5,6)}
shots={Coord(5,5):True, Coord(5,6):True}
adj=sum(1 for _ in range(50) if (lambda s: s and (abs(s.r-5)+abs(s.c-5)==1 or abs(s.r-5)+abs(s.c-6)==1))(ai_next("normal", shots, [2], rng, sunk_shots)))
check(f"normal ignores sunk ship ({adj}/50 adjacent)", adj < 15)
shots={Coord(5,5):True, Coord(5,6):True, Coord(2,2):True, Coord(2,3):True}
sunk_line=live_line=0
for _ in range(50):
    s=ai_next("hard", shots, [2], rng, sunk_shots)
    if s and s.r==5 and s.c in (4,7): sunk_line+=1
    if s and s.r==2 and s.c in (1,4): live_line+=1
check(f"hard prefers live hit line over sunk ({live_line} vs {sunk_line})", live_line > sunk_line)

print("Extra rules")
g3 = Game()
check("fire before battle invalid, turn unchanged", g3.fire(Coord(0,0),"P1")=="invalid" and g3.turn=="P1")
g3.p1 = random_fleet(rng); g3.p2 = random_fleet(rng); g3.start()
check("fire outside grid invalid", g3.fire(Coord(10,0),"P1")=="invalid")
f2 = Fleet()
f2.place(Ship("Carrier",5,Coord(0,0),True))
check("moving a ship replaces it", f2.place(Ship("Carrier",5,Coord(5,5),False)) and len(f2.ships)==1 and f2.ships[0].origin==Coord(5,5))

print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
