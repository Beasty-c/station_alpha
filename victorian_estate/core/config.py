"""
Dimensional and stylistic specification for the estate.

All units are metres; the scene is built at 1 Blender unit = 1 m so that
Cycles' physically-based shading, sun angles and depth of field behave
sensibly without rescaling.

The house is a Queen Anne / Second Empire hybrid of the sort built for
American industrialists between roughly 1875 and 1895: asymmetric massing,
a corner tower, a wrap-around veranda, steep cross gables, a slate mansard
over the main block, and a great deal of turned and sawn woodwork.
"""

from dataclasses import dataclass, field


# ---------------------------------------------------------------------------
# Global site layout
# ---------------------------------------------------------------------------

#: Half-width of the square parcel of land the estate occupies.
SITE_HALF = 130.0

#: The house sits north of the origin; the drive approaches from the south.
HOUSE_ORIGIN = (0.0, 0.0)

#: Height of the finished ground floor above site datum (the plinth).
GRADE = 0.0


# ---------------------------------------------------------------------------
# Storey heights
# ---------------------------------------------------------------------------

BASEMENT_SHOW = 1.30      # exposed rusticated basement / water table
FLOOR_1 = 4.10            # piano nobile - the tall public rooms
FLOOR_2 = 3.70            # principal bedrooms
FLOOR_3 = 3.20            # secondary bedrooms, within the mansard
BAND_1 = 0.45             # belt course thickness between 1 and 2
BAND_2 = 0.40             # belt course between 2 and 3

#: Absolute Z of each floor level, measured to the top of the floor deck.
Z_BASE = GRADE
Z_F1 = Z_BASE + BASEMENT_SHOW
Z_F2 = Z_F1 + FLOOR_1
Z_F3 = Z_F2 + FLOOR_2
Z_CORNICE = Z_F3 + FLOOR_3


# ---------------------------------------------------------------------------
# Main block
# ---------------------------------------------------------------------------

@dataclass(frozen=True)
class Block:
    """An axis-aligned rectangular mass of the house."""
    name: str
    cx: float
    cy: float
    sx: float      # full width  (X)
    sy: float      # full depth  (Y)
    z0: float
    z1: float

    @property
    def x0(self) -> float: return self.cx - self.sx / 2.0

    @property
    def x1(self) -> float: return self.cx + self.sx / 2.0

    @property
    def y0(self) -> float: return self.cy - self.sy / 2.0

    @property
    def y1(self) -> float: return self.cy + self.sy / 2.0

    @property
    def height(self) -> float: return self.z1 - self.z0


#: The principal mass: 3 storeys under a mansard.
MAIN = Block("main", 0.0, 0.0, 19.0, 14.0, Z_BASE, Z_CORNICE)

#: The service wing runs north (behind) the main block, one storey lower.
WING = Block("wing", -2.0, -11.4, 11.0, 9.6, Z_BASE, Z_F3 + FLOOR_3 * 0.55)

#: A projecting gabled pavilion on the east elevation.
PAVILION = Block("pavilion", 11.6, 2.6, 6.4, 8.2, Z_BASE, Z_CORNICE - 0.9)

BLOCKS = (MAIN, WING, PAVILION)


# ---------------------------------------------------------------------------
# Corner tower (south-west)
# ---------------------------------------------------------------------------

TOWER_CX = -9.0
TOWER_CY = 6.6
TOWER_R = 2.75            # radius at the shaft
TOWER_SIDES = 24          # octagonal-ish but read as round at distance
TOWER_TOP = Z_CORNICE + FLOOR_3 * 0.35
TOWER_SPIRE_H = 8.6
TOWER_FINIAL_H = 2.2


# ---------------------------------------------------------------------------
# Veranda / porch
# ---------------------------------------------------------------------------

VERANDA_DEPTH = 3.40
VERANDA_DECK_Z = Z_F1 - 0.22
VERANDA_CEIL_Z = Z_F1 + 3.25
VERANDA_POST_BAY = 2.55   # nominal spacing between turned posts
VERANDA_RAIL_H = 0.95
BALUSTER_SPACING = 0.155


# ---------------------------------------------------------------------------
# Roof
# ---------------------------------------------------------------------------

MANSARD_LOWER_RUN = 1.05      # horizontal run of the steep lower slope
MANSARD_LOWER_RISE = 4.20
MANSARD_UPPER_RISE = 1.55
EAVE_OVERHANG = 0.85
CORNICE_DEPTH = 0.95
CRESTING_H = 0.55             # cast-iron ridge cresting

SLATE_W = 0.30
SLATE_H = 0.42
SLATE_EXPOSURE = 0.16         # how much of each course shows


# ---------------------------------------------------------------------------
# Fenestration
# ---------------------------------------------------------------------------

WIN_W = 1.14                  # typical 2-over-2 sash opening width
WIN_H_1 = 2.85                # ground floor - tall
WIN_H_2 = 2.35
WIN_H_3 = 1.85
WIN_SILL = 0.95               # sill height above the floor deck
MUNTIN = 0.035
SASH_RAIL = 0.075
GLASS_INSET = 0.055


# ---------------------------------------------------------------------------
# Palette - a documented "painted lady" scheme
# ---------------------------------------------------------------------------

PALETTE = {
    # Body: warm olive-sage clapboard
    "body":        (0.212, 0.216, 0.157),
    # Trim: a heavy cream, used for cornices, casings, columns
    "trim":        (0.796, 0.741, 0.596),
    # Accent: deep oxblood for sash, panel fields, door
    "accent":      (0.278, 0.086, 0.075),
    # Shadow accent: a bronze-green for brackets and spindle work
    "accent_dark": (0.098, 0.129, 0.114),
    # Highlight: gilded ochre picking out carved detail
    "gilt":        (0.545, 0.396, 0.145),
    "slate":       (0.055, 0.062, 0.072),
    "slate_band":  (0.118, 0.075, 0.078),   # patterned band courses
    "brick":       (0.176, 0.075, 0.058),
    "stone":       (0.392, 0.365, 0.318),
    "iron":        (0.021, 0.022, 0.024),
    "copper":      (0.196, 0.318, 0.259),
    "gravel":      (0.235, 0.212, 0.180),
    "lawn":        (0.078, 0.145, 0.043),
    "hedge":       (0.045, 0.098, 0.036),
    "bark":        (0.086, 0.068, 0.052),
    "leaf":        (0.061, 0.130, 0.040),
    "water":       (0.032, 0.055, 0.058),
    "marble":      (0.760, 0.748, 0.716),
}


# ---------------------------------------------------------------------------
# Grounds
# ---------------------------------------------------------------------------

DRIVE_WIDTH = 5.2
DRIVE_CIRCLE_R = 15.0         # centre-line radius of the carriage turn
DRIVE_CIRCLE_CY = 30.0        # south of the house

WALL_H = 2.05                 # perimeter estate wall
WALL_T = 0.55
GATE_X = 0.0
GATE_Y = 96.0

PARTERRE_CX = -34.0
PARTERRE_CY = 4.0
PARTERRE_SIZE = 30.0

FOUNTAIN_XY = (0.0, DRIVE_CIRCLE_CY)
FOUNTAIN_R = 6.2

CONSERVATORY_XY = (24.0, -6.0)
CARRIAGE_HOUSE_XY = (-27.0, -30.0)
GAZEBO_XY = (38.0, 34.0)
POND_XY = (44.0, -34.0)


# ---------------------------------------------------------------------------
# Detail level - lets the whole estate be rebuilt cheaply while iterating.
# ---------------------------------------------------------------------------

@dataclass
class Detail:
    """Global tessellation / instancing budget."""
    lathe_segments: int = 20      # radial segments on turned work
    lathe_profile: int = 1        # profile subdivision multiplier
    balusters: bool = True
    spindle_frieze: bool = True
    slate_individual: bool = True  # model every slate, or use a texture
    trees: int = 90
    shrubs: int = 260
    grass_clumps: int = 0          # particle-scattered grass (expensive)
    interior: bool = True

    @classmethod
    def draft(cls) -> "Detail":
        return cls(lathe_segments=8, lathe_profile=0, balusters=True,
                   spindle_frieze=False, slate_individual=False,
                   trees=24, shrubs=60, interior=False)

    @classmethod
    def full(cls) -> "Detail":
        return cls(lathe_segments=28, lathe_profile=2, slate_individual=True,
                   trees=140, shrubs=420, grass_clumps=0, interior=True)


DETAIL = Detail()
