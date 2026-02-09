# ocean-tiles
These files are used to create a Earth map canvas.

### Before you get started
You have to change your canvas options on ppf instance to make the correct colors and size on the canvas  
<details>
<summary>Example canvas settings</summary>
<pre>"0": {
    "ident":"d",
    "colors": [
      [ 202, 227, 255 ],
      [ 255, 255, 255 ],
      [ 255, 255, 255 ],
      [ 228, 228, 228 ],
      [ 196, 196, 196 ],
      [ 136, 136, 136 ],
      [ 78, 78, 78 ],
      [ 0, 0, 0 ],
      [ 244, 179, 174 ],
      [ 255, 167, 209 ],
      [ 255, 84, 178 ],
      [ 255, 101, 101 ],
      [ 229, 0, 0 ],
      [ 154, 0, 0 ],
      [ 254, 164, 96 ],
      [ 229, 149, 0 ],
      [ 160, 106, 66 ],
      [ 96, 64, 40 ],
      [ 245, 223, 176 ],
      [ 255, 248, 137 ],
      [ 229, 217, 0 ],
      [ 148, 224, 68 ],
      [ 2, 190, 1 ],
      [ 104, 131, 56 ],
      [ 0, 101, 19 ],
      [ 202, 227, 255 ],
      [ 0, 211, 221 ],
      [ 0, 131, 199 ],
      [ 0, 0, 234 ],
      [ 25, 25, 115 ],
      [ 207, 110, 228 ],
      [ 130, 0, 128 ]
    ],
    "size": 65536,
    "cli": 2,
    "bcd": 4000,
    "pcd": 7000,
    "cds": 60000,
    "ranked": true
  },
</pre>
</details>

# Creating a map
There are two ways Earth map can be done

## Using premade upscaled tiles
1. unpack `ocean.tar.xz` or `ocean-dithered.tar.xz`
2. start drawOcean script (do not forget to install packages via `npm install` and enable redis server)
```
node drawOcean.js
```

## Generate ocean tiles
In order to have the ocean and land on the canvas, we have to scale up the ocean.png, create tiles and then upload them to the canvas with drawOcean.js.

Execute those shell commands in this folder (utils/ocean-tiles). Imagemagick needs to be installed.

- create folder for tiles:

```
mkdir ./ocean
cd ocean
```
- to split image into tiles:

```
magick ../ocean.png -crop 128x128 +adjoin ocean_tiles.png
```
- upscale and convert to black and white

```
mogrify -resize 2048x2048 -colors 2 -white-threshold 80% -black-threshold 80% ocean_tiles*.png
```
or without dithering:

```
mogrify +dither -resize 2048x2048 -colors 2 -white-threshold 80% -black-threshold 80% ocean_tiles*.png
```
- create subfolders (this doesn't work on windows)

```
for i in {0..31}; do mkdir $i; done
```
- put into subfolders (this doesn't work on windows)

```
for file in ./ocean_tiles*.png; do NUM=`echo $file | sed -e 's/.*ocean_tiles//' -e 's/.png//'`; Y=$(expr $NUM / 32); X=$(expr $NUM % 32); newfile="$X/$Y.png"; mv $file $newfile; done
```
- Draws the 2048x2048 tiles from the ./ocean directory on the canvas. Uses localhost:6379 as redis url, if you need a different one, edit it in the drawOcean.js file.

```
cd ../
node drawOcean.js
```
