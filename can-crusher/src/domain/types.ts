/** Shared value types for the Can Crusher domain. */

/**
 * The state of the world at the instant the sole reaches the top of the can.
 * Offsets are the sole centre minus the can axis, so a positive `offsetX`
 * means the foot landed to the right of the can.
 */
export interface Impact {
  /** Sideways offset of the sole centre from the can axis, in world units. */
  offsetX: number;
  /** Front/back offset of the sole centre from the can axis, in world units. */
  offsetZ: number;
  /** Foot pitch, in radians, about world X. Positive dips the far edge. */
  tiltX: number;
  /** Foot roll, in radians, about world Z. Positive dips the left edge. */
  tiltZ: number;
  /** Downward energy delivered, 0 (a tap) to 1 (a full-height stomp). */
  power: number;
}

/** A planar direction. Zero length means "no preferred direction". */
export interface Vec2 {
  x: number;
  z: number;
}

/** How the can ends up looking. Everything the renderer needs to draw it. */
export interface CrushOutcome {
  /** False when the sole missed the can entirely. */
  contact: boolean;
  /** Fraction of the can's lid the sole covered, 0 to 1. */
  coverage: number;
  /** Final height as a fraction of the pristine height, MIN_HEIGHT_RATIO to 1. */
  heightRatio: number;
  /** 0 for an even concertina crush, 1 for a can folded flat to one side. */
  asymmetry: number;
  /** How far the crushed can leans, in radians. */
  foldAngle: number;
  /** How far the whole can topples about its base rim, in radians. */
  tipAngle: number;
  /** Unit direction the can folds and skids towards. Zero for a clean crush. */
  escapeDir: Vec2;
  /** How hard the can squirts out from under the sole, 0 to 1. */
  launch: number;
  /** Outward bulge of the can waist, 0 to 1. Only clean crushes bulge. */
  bulge: number;
  /** Height fraction the buckle forms at, 0.5 for a centred crush. */
  buckleHeight: number;
  /** Radial distance of the impact from the can axis. */
  offsetDistance: number;
  /** Total foot tilt at impact, in radians. */
  tiltMagnitude: number;
  /** Offset beyond the dead zone; 0 means "as central as the game asks for". */
  offsetError: number;
  /** Tilt beyond the dead zone, in radians. */
  tiltError: number;
  /** Power actually delivered after clamping. */
  power: number;
}

/** The five result bands. */
export type ResultLabel =
  | 'Perfect Crush'
  | 'Clean Stomp'
  | 'Bent It'
  | 'Glancing Blow'
  | 'Miss';

/** A scored stomp, ready for display. */
export interface ScoreBreakdown {
  /** Final score, an integer from 0 through 100. */
  score: number;
  label: ResultLabel;
  /** One short sentence saying what went right or wrong. */
  explanation: string;
  /** The four sub-scores, each 0 to 1, for the score bars in the HUD. */
  components: {
    centering: number;
    uprightness: number;
    flatness: number;
    symmetry: number;
  };
}
