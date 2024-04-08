import cv2
from skimage import measure, color
import matplotlib.pyplot as plt
testRect = {
    "audit_type": "rect",
    "id": 27,
    "page_number": 1,
    "template_signatory_id": 10,
    "x1": 0.122898037659841,
    "x2": 0.169011505478072,
    "y1": 0.912442396313364,
    "y2": 0.943205053865169
}
source_image = cv2.imread("test_files/VacantLandContract - Signed [1] (1)-0.png")
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
cv2.imwrite("output_files/Step One Cropped.png", cropped)
sharpened = unsharp_mask(cropped)
cv2.imwrite("output_files/Step Two Sharpened.png", sharpened)
img = cv2.threshold(sharpened, 127, 255, cv2.THRESH_BINARY)[1]
blobs = img > img.mean()
blobs_labels = measure.label(blobs, background=1)
image_label_overlay = color.label2rgb(blobs_labels, image=img)
fig, ax = plt.subplots(figsize=(10, 6))
ax.imshow(image_label_overlay)
ax.set_axis_off()
plt.tight_layout()
plt.show()
