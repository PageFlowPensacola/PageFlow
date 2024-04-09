import cv2
from skimage import measure, color, morphology
import matplotlib.pyplot as plt
import numpy as np

testRect = {
    "audit_type": "rect",
    "id": 35,
    "page_number": 13,
    "template_signatory_id": 14,
    "x1": 0.555070650349437,
    "x2": 0.955565050202948,
    "y1": 0.824091311380352,
    "y2": 0.860164189580981
}
source_image = cv2.imread("test_files/OneInitialsSet-12.png")
img = cv2.cvtColor(source_image, cv2.COLOR_BGR2GRAY)

def translate_coords(coord1, coord2, span):
    return [int(coord1 * span), int(coord2 * span)]

def unsharp_mask(image):
    """Soften an input image.

    Parameters
    ----------
    image : numpy ndarray
        The input image.

    Returns
    -------
    numpy ndarray
        The soften image.

    """
    # perform GaussianBlur filter to use it in unsharpening mask
    gaussian_3 = cv2.GaussianBlur(image, (9, 9), 10.0)
    # calculates the weighted sum of two arrays (source image and GaussianBlur
    # filter) to perform unsharpening mask
    unsharp_image = cv2.addWeighted(image, 1.5, gaussian_3, -0.5, 0, image)
    # return unsharpened image
    return unsharp_image

cropped = img[slice(*translate_coords(testRect['y1'], testRect['y2'], source_image.shape[0])), slice(*translate_coords(testRect['x1'], testRect['x2'], source_image.shape[1]))]
cv2.imwrite("output_files/Step One Unmodified.png", img)
cv2.imwrite("output_files/Step Two Cropped.png", cropped)
sharpened = unsharp_mask(cropped)
cv2.imwrite("output_files/Step Three Sharpened.png", sharpened)
img = cv2.threshold(sharpened, 127, 255, cv2.THRESH_BINARY)[1]
blobs = img > img.mean()
blobs_labels = measure.label(blobs, background=1)

image_label_overlay = color.label2rgb(blobs_labels, image=img)
fig, ax = plt.subplots(figsize=(20, 12))
ax.imshow(image_label_overlay)
ax.set_axis_off()
plt.tight_layout()
plt.show()

the_biggest_component = 0
total_area = 0
counter = 0
average = 0.0
for region in measure.regionprops(blobs_labels):
		if (region.area > 10):
				total_area = total_area + region.area
				counter = counter + 1
		# print region.area # (for debugging)
		# take regions with large enough areas
		if (region.area >= 80):
				if (region.area > the_biggest_component):
						the_biggest_component = region.area

average = (total_area/counter)
print("the_biggest_component: " + str(the_biggest_component))
print("average: " + str(average))
