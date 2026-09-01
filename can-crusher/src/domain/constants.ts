/**
 * Physical constants for the play field.
 *
 * One world unit is roughly one decimetre. A 330 ml can is 66 mm across and
 * 122 mm tall, which lands on the numbers below.
 */

/** Radius of the pristine can. */
export const CAN_RADIUS = 0.33;
/** Height of the pristine can. */
export const CAN_HEIGHT = 1.22;

/** Half width of the shoe sole, across the foot (world X). */
export const FOOT_HALF_WIDTH = 0.42;
/** Half length of the shoe sole, along the foot (world Z). */
export const FOOT_HALF_LENGTH = 0.95;

/** Radial distance beyond which the sole can no longer touch the can at all. */
export const MAX_CONTACT_RADIUS = CAN_RADIUS + FOOT_HALF_WIDTH;

/** Foot tilt, in radians, at which a stomp counts as a full edge strike. */
export const MAX_TILT = 0.45;

/** Height the can is squashed to by a flawless stomp, as a fraction of CAN_HEIGHT. */
export const MIN_HEIGHT_RATIO = 0.16;

/** Widest angle the crushed can folds over to. */
export const MAX_FOLD_ANGLE = 1.05;

/** Widest angle the whole can topples about its base rim. */
export const MAX_TIP_ANGLE = 0.6;

/**
 * Errors below these thresholds are treated as flawless. Without a dead zone a
 * score of 100 would need floating-point-exact alignment, which no player can
 * hit; with it, 100 needs an offset inside 6% of the can radius and a foot
 * within 1.4 degrees of level.
 */
export const CENTER_DEAD_ZONE = 0.03;
export const TILT_DEAD_ZONE = 0.03;
export const POWER_DEAD_ZONE = 0.95;

/** Offset at which the centring term has decayed to 1/e. */
export const CENTER_SIGMA = 0.17;

/** How far the player may move the aim reticle from the middle of the slab. */
export const AIM_LIMIT_X = 1.5;
export const AIM_LIMIT_Z = 1.1;

/** How far the can may be displaced from the middle of the slab between rounds. */
export const CAN_JITTER_X = 0.5;
export const CAN_JITTER_Z = 0.3;
