import pickle
import os
from tqdm import tqdm
import rasterio
from affine import Affine
import numpy as np
import scipy.ndimage
from rasterio.warp import reproject, Resampling
import PIL
import matplotlib.pyplot as plt
from base64 import b64encode
from io import StringIO, BytesIO
from ipyleaflet import Map, Popup, ImageOverlay
from ipywidgets import ToggleButtons
from IPython.display import display
from delineate import delineate, download

def process_acc(path):
    dataset = rasterio.open(path)
    acc_orig = dataset.read()[0]
    acc = np.clip(acc_orig, 0, np.inf)
    shrink = 2 # if you are out of RAM try increasing this number (should be a power of 2)
    radius = 5 # you can play with this number to change the width of the rivers
    circle = np.zeros((2*radius+1, 2*radius+1)).astype('uint8')
    y, x = np.ogrid[-radius:radius+1,-radius:radius+1]
    index = x**2 + y**2 <= radius**2
    circle[index] = 1
    acc = np.sqrt(acc)
    acc = scipy.ndimage.maximum_filter(acc, footprint=circle)
    acc[acc_orig<0] = np.nan
    acc = np.array(acc[::shrink, ::shrink])
    affine = dataset.affine * Affine.scale(shrink)
    return acc, affine, dataset.bounds

def to_webmercator(source, affine, bounds):
    with rasterio.Env():
        rows, cols = source.shape
        src_transform = list(affine)
        src_transform = Affine(*src_transform[:6])
        src_crs = {'init': 'EPSG:4326'}
        dst_crs = {'init': 'EPSG:3857'}
        dst_transform, width, height = rasterio.warp.calculate_default_transform(src_crs, dst_crs, cols, rows, *bounds)
        dst_shape = height, width
        destination = np.zeros(dst_shape)
        reproject(
            source,
            destination,
            src_transform=src_transform,
            src_crs=src_crs,
            dst_transform=dst_transform,
            dst_crs=dst_crs,
            resampling=Resampling.nearest)
    return destination

def get_img(a_web, path=None):
    a_norm = a_web - np.nanmin(a_web)
    a_norm = a_norm / np.nanmax(a_norm)
    a_norm = np.where(np.isfinite(a_web), a_norm, 0)
    a_im = PIL.Image.fromarray(np.uint8(plt.cm.jet(a_norm)*255))
    a_mask = np.where(np.isfinite(a_web), 255, 0)
    mask = PIL.Image.fromarray(np.uint8(a_mask), mode='L')
    im = PIL.Image.new('RGBA', a_norm.shape[::-1], color=None)
    im.paste(a_im, mask=mask)
    f = BytesIO()
    im.save(f, 'png')
    data = b64encode(f.getvalue())
    data = data.decode('ascii')
    imgurl = 'data:image/png;base64,' + data
    if path is not None:
        with open(path, 'wb') as f:
            pickle.dump(imgurl, f)
    return imgurl

def show_flow(coord, m):
    lat, lon = coord
    url = None
    b = [5, 39, -119, -60]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/ca_acc_30s_grid.zip'
        bounds = b
    b = [-56, 15, -93, -32]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/sa_acc_30s_grid.zip'
        bounds = b
    b = [24, 61, -138, -52]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/na_acc_30s_grid.zip'
        bounds = b
    b = [-35, 38, -19, 55]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/af_acc_30s_grid.zip'
        bounds = b
    b = [12, 62, -14, 70]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/eu_acc_30s_grid.zip'
        bounds = b
    b = [-56, -10, 112, 180]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/au_acc_30s_grid.zip'
        bounds = b
    b = [-12, 61, 57, 180]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_30s_zip_grid/as_acc_30s_grid.zip'
        bounds = b
    if url is None:
        print('Position not covered.')
        return
    adffile = download(url)
    imgfile = adffile.replace('.adf', '.pkl')
    if os.path.exists(imgfile):
        with open(imgfile, 'rb') as f:
            imgurl = pickle.load(f)
    else:
        acc, affine, bounds2 = process_acc(adffile)
        acc_web = to_webmercator(acc, affine, bounds2)
        imgurl = get_img(acc_web, imgfile)
    io = ImageOverlay(url=imgurl, bounds=[(bounds[0], bounds[2]), (bounds[1], bounds[3])])
    m.add_layer(io)
    slider = io.interact(opacity=(0.0,1.0,0.01))
    display(slider)

def get_choice(x):
    global m, s, p, c
    s.close()
    m.remove_layer(p)
    choice = x['new']
    if choice == 'Show flow':
        show_flow(c, m)
    elif choice == 'Delineate watershed':
        ws = delineate(*c)
        mask = ws['mask'][0].astype('float32')
        mask[mask==0] = np.nan
        bounds = [ws['latlon'][0][1], ws['latlon'][0][0]-mask.shape[0]/240, ws['latlon'][0][1]+mask.shape[1]/240, ws['latlon'][0][0]]
        affine = [1/240, 0, ws['latlon'][0][1], 0, -1/240, ws['latlon'][0][0], 0, 0, 1]
        ws_web = to_webmercator(mask, affine, bounds)
        imgurl = get_img(ws_web)
        bounds2 = [(bounds[1], bounds[0]), (bounds[3], bounds[2])]
        io = ImageOverlay(url=imgurl, bounds=bounds2)
        m.add_layer(io)
        slider = io.interact(opacity=(0.0,1.0,0.01))
        display(slider)

def show_menu(event, type, coordinates):
    global m, s, p, c
    if type == 'contextmenu':
        s = ToggleButtons(options=['Show flow', 'Delineate watershed'], value=None)
        s.observe(get_choice, names='value')
        p = Popup(location=coordinates, child=s, max_width=160)
        m.add_layer(p)
        c = coordinates
