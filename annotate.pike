int main (int argc, array(string) argv){
	if (argc < 3){
		exit(1, "Usage: %s <inputfilename> <outputfilename>\n", argv[0]);
	}

	object img = Image.PNG.decode(Stdio.read_file(argv[1]));
	int right, bottom;
	int left = img->xsize();
	int top = img->ysize();

	mapping rc = Process.run(({"tesseract", argv[1], "-", "makebox"}));
	foreach(rc->stdout / "\n", string line){
		array(string) parts = line / " ";
		if (sizeof(parts) < 6){
			continue;
		}
		if (parts[0] == "~"){
			continue;
		}
		int x1 = (int)parts[1];
		int y1 = img->ysize() - (int)parts[2];
		int x2 = (int)parts[3];
		int y2 = img->ysize() - (int)parts[4];
		img->line(x1, y1, x2, y1);
		img->line(x2, y1, x2, y2);
		img->line(x2, y2, x1, y2);
		img->line(x1, y2, x1, y1);
		left = min(left, (x1 + x2) / 2);
		top = min(top, (y1 + y2) / 2);
		right = max(right, (x1 + x2) / 2);
		bottom = max(bottom, (y1 + y2) / 2);
	}
	img->setcolor(@bbox_color);
	img->line(left, top, right, top);
	img->line(right, top, right, bottom);
	img->line(right, bottom, left, bottom);
	img->line(left, bottom, left, top);
	img->line(left, top, right, bottom);
	img->line(right, top, left, bottom);

	Stdio.write_file(argv[2], Image.PNG.encode(img));
}
