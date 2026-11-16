package shapes

/** A point on the plane. */
Point :: struct {
    /**< Across. */
    x : int,
    y : int,
}

/**
 * The point moved.
 *
 * @param point Where it starts.
 * @param by How far across.
 * @return Where it ends.
 */
moved :: fn(point : Point, by : int) -> Point {
    return Point.{ x = point.x + by, y = point.y }
}
