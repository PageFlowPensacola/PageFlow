import json
import numpy as np
import sys

def find_affine_transformation(points):
	"""
	Find the affine transformation matrix for a given set of points.

	points should be a sequence of 4-tuples with original and destination
	coordinates.

	Returns: affine_matrix of shape (2, 3)
	"""
	n = len(points) * 2
	A = np.zeros((n, 6))
	B = np.zeros(n)

	i = 0
	for x1, y1, x2, y2 in points:
		A[i] = [x1, y1, 1, 0, 0, 0]
		B[i] = x2
		i += 1
		A[i] = [0, 0, 0, x1, y1, 1]
		B[i] = y2
		i += 1

	# Solve for the affine transformation parameters
	affine_params, residuals, rank, s = np.linalg.lstsq(A, B, rcond=None)
	print("Orientation Details: \n residuals: ", residuals, file=sys.stderr)
	print("rank: ", rank, file=sys.stderr)
	print("s: ", s, file=sys.stderr)
	return affine_params

try:
	while True:
		points = json.loads(input())
		affine_matrix = find_affine_transformation(points)
		print(json.dumps(list(affine_matrix)))
except EOFError: pass
