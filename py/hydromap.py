import pickle
import os
from tqdm import tqdm
import rasterio
import rasterio.features
from affine import Affine
import numpy as np
import scipy.ndimage
from rasterio import transform
from rasterio.warp import reproject, Resampling
import PIL
import matplotlib.pyplot as plt
from base64 import b64encode
from io import StringIO, BytesIO
from ipyleaflet import Map, Popup, ImageOverlay, Polygon
from ipywidgets import ToggleButtons
from IPython.display import display
from delineate import delineate, download

accDelta = np.inf

def to_webmercator(source, affine, bounds):
    with rasterio.Env():
        rows, cols = source.shape
        src_transform = affine
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

def get_img(a_web):
    if (np.all(np.isnan(a_web))):
        a_web[:, :] = 0
        a_norm = a_web
    else:
        a_norm = a_web - np.nanmin(a_web)
        a_norm = a_norm / np.nanmax(a_norm)
        a_norm = np.where(np.isfinite(a_web), a_norm, 0)
    a_im = PIL.Image.fromarray(np.uint8(plt.cm.viridis(a_norm)*255))
    a_mask = np.where(np.isfinite(a_web), 255, 0)
    mask = PIL.Image.fromarray(np.uint8(a_mask), mode='L')
    im = PIL.Image.new('RGBA', a_norm.shape[::-1], color=None)
    im.paste(a_im, mask=mask)
    f = BytesIO()
    im.save(f, 'png')
    data = b64encode(f.getvalue())
    data = data.decode('ascii')
    imgurl = 'data:image/png;base64,' + data
    return imgurl

def show_acc(label, coord, m, current_url, current_acc, current_io, width):
    lat, lon = coord
    url = None
    b = [5, 39, -119, -60]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/ca_acc_15s_grid.zip'
        bounds = b
    b = [-56, 15, -93, -32]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/sa_acc_15s_grid.zip'
        bounds = b
    b = [24, 61, -138, -52]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/na_acc_15s_grid.zip'
        bounds = b
    b = [-35, 38, -19, 55]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/af_acc_15s_grid.zip'
        bounds = b
    b = [12, 62, -14, 70]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/eu_acc_15s_grid.zip'
        bounds = b
    b = [-56, -10, 112, 180]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/au_acc_15s_grid.zip'
        bounds = b
    b = [-12, 61, 57, 180]
    if (url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/as_acc_15s_grid.zip'
        bounds = b
    if url is None:
        return current_url, current_acc, current_io, 0
    if url == current_url:
        acc = current_acc
    else:
        adffile = download(url, label)
        dataset = rasterio.open(adffile)
        acc = dataset.read()[0]

    y0 = int((bounds[1] - lat) * 240) - width
    y1 = y0 + 2 * width + 1
    x0 = int((lon - bounds[2]) * 240) - width
    x1 = x0 + 2 * width + 1
    lon0 = bounds[2] + x0 / 240
    lat0 = bounds[1] - y0 / 240
    acc_orig = np.array(acc[y0:y1, x0:x1])

    acc_width = np.sqrt(np.clip(acc_orig, 0, np.inf))
    if False:
        mask = np.ones((2*width+1, 2*width+1)) #.astype('uint8')
        mask[:, :] = np.nan
        y, x = np.ogrid[-width:width+1,-width:width+1]
        index = x**2 + y**2 <= width**2
        mask[index] = 1
        acc_width *= mask

        radius = 5 # you can play with this number to change the radius of the rivers
        circle = np.zeros((2*radius+1, 2*radius+1)).astype('uint8')
        y, x = np.ogrid[-radius:radius+1,-radius:radius+1]
        index = x**2 + y**2 <= radius**2
        circle[index] = 1
        acc_width = scipy.ndimage.maximum_filter(acc_width, footprint=circle)
    acc_width[acc_orig<0] = np.nan

    bounds2 = [lon0, lat0 - (2 * width + 1) / 240, lon0 + (2 * width + 1) / 240, lat0]
    affine = Affine(1/240, 0.0, lon0, 0.0, -1/240, lat0)
    acc_web = acc_width #to_webmercator(acc_width, affine, bounds2)
    imgurl = get_img(acc_web)
    io = ImageOverlay(url=imgurl, bounds=[(bounds2[1], bounds2[0]), (bounds2[3], bounds2[2])], opacity=0.5)
    if current_io is not None:
        m.remove_layer(current_io)
    m.add_layer(io)
    return url, acc, io, acc[y0+width, x0+width]

class Flow(object):
    def __init__(self, m, label):
        self.m = m
        self.label = label
        self.width = 10
        self.coord = None
        self.url = None
        self.acc = None
        self.io = None
        self.accDelta = np.inf
        self.s = None
        self.p = None
        self.show_flow = False
        self.show_menu = False
    def show(self, **kwargs):
        if kwargs.get('type') == 'contextmenu':
            self.show_menu = True
            if self.show_flow:
                showHideFlow = 'Hide flow'
            else:
                showHideFlow = 'Show flow'
            if showHideFlow == 'Hide flow':
                self.s = ToggleButtons(options=[showHideFlow, 'Delineate watershed', 'Close'], value=None)
            else:
                self.s = ToggleButtons(options=[showHideFlow, 'Close'], value=None)
            self.s.observe(self.get_choice, names='value')
            self.p = Popup(location=self.coord, child=self.s, max_width=160, close_button=False, auto_close=True, close_on_escape_key=False)
            self.m.add_layer(self.p)
        elif not self.show_menu:
            if kwargs.get('type') == 'mousemove':
                self.coord = kwargs.get('coordinates')
                if self.show_flow:
                    self.url, self.acc, self.io, flow = show_acc(self.label, self.coord, self.m, self.url, self.acc, self.io, self.width)
                    self.label.value = f'lat/lon = {self.coord}, flow = {flow}'
                else:
                    self.label.value = f'lat/lon = {self.coord}'
                    pass
            elif 'width' in kwargs:
                self.width = (kwargs.get('width') - 1) // 2
                if self.coord and self.show_flow:
                    self.url, self.acc, self.io, flow = show_acc(self.label, self.coord, self.m, self.url, self.acc, self.io, self.width)
    def get_choice(self, x):
        self.show_menu = False
        self.s.close()
        self.m.remove_layer(self.p)
        self.p = None
        choice = x['new']
        if choice == 'Show flow':
            self.show_flow = True
        elif choice == 'Hide flow':
            self.show_flow = False
            self.m.remove_layer(self.io)
            self.io = None
        elif choice == 'Delineate watershed':
            self.label.value = 'Delineating watershed, please wait...'
            #lat, lon = [np.floor(i * 240) / 240 + 1 / 240 for i in self.coord]
            ws = delineate(*self.coord, accDelta=self.accDelta)
            self.label.value = 'Watershed delineated'
            mask = np.zeros(ws['bbox'][2:], dtype='float32')
            for mask_idx in range(len(ws['mask'])):
                y0 = int(round((ws['bbox'][0] - ws['latlon'][mask_idx][0]) * 240))
                y1 = int(round(y0 + ws['mask'][mask_idx].shape[0]))
                x0 = int(round((ws['latlon'][mask_idx][1] - ws['bbox'][1]) * 240))
                x1 = int(round(x0 + ws['mask'][mask_idx].shape[1]))
                mask[y0:y1, x0:x1] = mask[y0:y1, x0:x1] + ws['mask'][mask_idx].astype('float32') * (1 - np.random.rand())
            if False:
                np.save('tmp/mask.npy', ws['mask'][0].astype('uint8'))
                #print('bbox: ' + str(ws['bbox']))
                mask[mask==0] = np.nan
                bounds = [ws['bbox'][1], ws['bbox'][0]-ws['bbox'][2]/240, ws['bbox'][1]+ws['bbox'][3]/240, ws['bbox'][0]]
                #bounds = [ws['latlon'][0][1], ws['latlon'][0][0]-mask.shape[0]/240, ws['latlon'][0][1]+mask.shape[1]/240, ws['latlon'][0][0]]
                affine = Affine(1/240, 0, ws['bbox'][1], 0, -1/240, ws['bbox'][0])
                #affine = Affine(1/240, 0, ws['latlon'][0][1], 0, -1/240, ws['latlon'][0][0])
                ws_web = to_webmercator(mask, affine, bounds)
                imgurl = get_img(ws_web)
                bounds2 = [(bounds[1], bounds[0]), (bounds[3], bounds[2])]
                io = ImageOverlay(url=imgurl, bounds=bounds2, opacity=0.5)
                self.m.add_layer(io)
            else:
                x0 = ws['latlon'][0][1]
                x1 = x0 + mask.shape[1] / 240
                y0 = ws['latlon'][0][0]
                y1 = y0 - mask.shape[0] / 240
                mask2 = np.zeros((mask.shape[0]+2, mask.shape[1]+2), dtype=np.float32)
                mask2[1:-1, 1:-1] = mask
                affine = Affine(1/240, 0, ws['latlon'][0][1]-1/240, 0, -1/240, ws['latlon'][0][0]+1/240)
                shapes = list(rasterio.features.shapes(mask2, transform=affine))
                polygons = []
                polygon = polygons
                for i, shape in enumerate(shapes[:-1]):
                    if i == 1:
                        # more than one polygon
                        polygons = [polygons]
                    if i >= 1:
                        polygons.append([])
                        polygon = polygons[-1]
                    for coord in shape[0]['coordinates'][0]:
                        x, y = coord
                        polygon.append((y, x))
                polygon = Polygon(locations=polygons, color='green', fill_color='green')
                self.m.add_layer(polygon)
            self.label.value = 'Watershed displayed'
            #slider = io.interact(opacity=(0.0,1.0,0.01))
            #display(slider)
        elif choice == 'Close':
            pass
