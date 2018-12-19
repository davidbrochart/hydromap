import sys
import os
from zipfile import ZipFile
import shutil
from numba import jit
import requests
import numpy as np
import rasterio

def download(url, label=None):
    filename = os.path.basename(url)
    name = filename[:filename.find('_grid')]
    adffile = 'tmp/' + name + '/' + name + '/w001001.adf'
    os.makedirs('tmp', exist_ok=True)
    if not os.path.exists(adffile):
        if label is not None:
            label.value = f'Please wait, downloading {url}'
        downloaded = False
        while not downloaded:
            try:
                r = requests.get(url, stream=True)
                with open('tmp/' + filename, 'wb') as f:
                    total_length = int(r.headers.get('content-length'))
                    for chunk in r.iter_content(chunk_size=1024):
                        if chunk:
                            f.write(chunk)
                            f.flush()
                downloaded = True
            except:
                pass
        zip = ZipFile('tmp/' + filename)
        zip.extractall('tmp/')
    return adffile

def delineate(lat, lon, _sub_latlon=[], accDelta=np.inf):
    getSubBass = True
    sample_i = 0
    samples = np.empty((1024, 2), dtype=np.float32)
    lengths = np.empty(1024, dtype=np.float32)
    labels = np.empty((1024, 3), dtype=np.int32)
    dirNeighbors = np.empty(1024, dtype=np.uint8)
    accNeighbors = np.empty(1024, dtype=np.uint32)
    ws_latlon = np.empty(2, dtype=np.float32)
    # output mask ->
    mxw = 3000 # bytes
    myw = mxw * 8 # bits
    mm = np.empty((myw, mxw), dtype = np.uint8)
    mm_back = np.empty((myw, mxw), dtype = np.uint8)
    mx0_deg = 0
    my0_deg = 0
    # <- output mask

    simple_delineation = False
    if len(_sub_latlon) == 0:
        sub_latlon = np.empty((1, 2), dtype=np.float32)
        sub_latlon[0, :] = [lat, lon]
        if not np.isfinite(accDelta):
            simple_delineation = True
    else:
        sub_latlon = np.empty((len(_sub_latlon), 2), dtype=np.float32)
        sub_latlon[:, :] = _sub_latlon
    _, _, _, _, lat0, lon0, pix_deg = getTileInfo(lat, lon)
    if simple_delineation:
        tiles = getTile(lat, lon, ['dir'])
        dir_tile = tiles['dir']
        acc_tile = dir_tile
        sample_size = 1
        samples[0] = [lat, lon]
    else:
        #print('Getting bassin partition...')
        tiles = getTile(lat, lon, ['dir', 'acc'])
        dir_tile = tiles['dir']
        acc_tile = tiles['acc']
        samples, labels, lengths, sample_size, mx0_deg, my0_deg, ws_mask, ws_latlon, dirNeighbors, accNeighbors = do_delineate(lat, lon, lat0, lon0, dir_tile, acc_tile, getSubBass, sample_i, samples, labels, lengths, pix_deg, accDelta, sub_latlon, mm, mm_back, mx0_deg, my0_deg, dirNeighbors, accNeighbors)
        if not is_empty_latlon(sub_latlon):
            print("WARNING: not all subbasins have been processed. This means that they don't fall into different pixels, or that they are not located in the basin. Please check their lat/lon coordinates.")
    #print('Delineating sub-bassins...')
    mask, latlon = [], []
    getSubBass = False
    lat_min = np.inf
    lat_max = -np.inf
    lon_min = np.inf
    lon_max = -np.inf
    for sample_i in range(sample_size):
        _, _, _, _, mx0_deg, my0_deg, ws_mask, ws_latlon, dirNeighbors, accNeighbors = do_delineate(lat, lon, lat0, lon0, dir_tile, acc_tile, getSubBass, sample_i, samples, labels, lengths, pix_deg, accDelta, sub_latlon, mm, mm_back, mx0_deg, my0_deg, dirNeighbors, accNeighbors)
        mask.append(ws_mask)
        latlon.append(ws_latlon)
        lat_min = min(lat_min, ws_latlon[0] - ws_mask.shape[0] / 240)
        lat_max = max(lat_max, ws_latlon[0])
        lon_min = min(lon_min, ws_latlon[1])
        lon_max = max(lon_max, ws_latlon[1] + ws_mask.shape[1] / 240)
    ws = {}
    if (lat_min == lat_max) and (lon_min == lon_max):
        ws['bbox'] = [lat_max, lon_min, mask[0].shape[0], mask[0].shape[1]]
    else:
        ws['bbox'] = [lat_max, lon_min, int(round((lat_max - lat_min) * 240)), int(round((lon_max - lon_min) * 240))]
    ws['outlet'] = samples[sample_size - 1::-1]
    ws['length'] = lengths[:sample_size]
    ws['mask'] = mask[::-1]
    ws['latlon'] = np.empty((sample_size, 2), dtype=np.float32)
    ws['latlon'][:, :] = latlon[::-1]
    # label reconstruction:
    ws['label'] = []
    for sample_i in range(sample_size):
        if sample_i == 0: # outlet subbassin
            ws['label'].append('0')
        else:
            i = labels[sample_i][0]
            ws['label'].append(ws['label'][i] + ',' + str(labels[sample_i][2]))
    return ws

@jit(nopython=True)
def get_length(lat, lon, lat0, lon0, olat, olon, dir_tile, pix_deg):
    x, y, _, _ = getXY(lat, lon, lat0, lon0, pix_deg)
    x_deg, y_deg = lon, lat
    if (abs(olon - lon) < pix_deg / 4) and (abs(olat - lat) < pix_deg / 4):
        return 0
    length = 0.
    done = False
    while not done:
        x_keep, y_keep = x, y
        _, x, y, _, _, x_deg, y_deg = go_get_dir(dir_tile[y, x], dir_tile, x, y, 0, 0, x_deg, y_deg, pix_deg)
        if x != x_keep and y != y_keep:
            length += 1.4142135623730951
        else:
            length += 1.
        if (abs(olon - x_deg) < pix_deg / 4) and (abs(olat - y_deg) < pix_deg / 4):
            done = True
    return length

@jit(nopython=True)
def do_delineate(lat, lon, lat0, lon0, dir_tile, acc_tile, getSubBass, sample_i, samples, labels, lengths, pix_deg, accDelta, sub_latlon, mm, mm_back, mx0_deg, my0_deg, dirNeighbors, accNeighbors):
    if getSubBass:
        x, y, x_deg, y_deg = getXY(lat, lon, lat0, lon0, pix_deg)
        acc = int(acc_tile[y,  x])
        samples[0, :] = [y_deg - pix_deg / 2, x_deg + pix_deg / 2]
        lengths[0] = 0
        rm_latlon(samples[0], sub_latlon, pix_deg)
        sample_i = 0
        labels[0, :] = [-1, 1, 0] # iprev, size, new_label
        label_i = 0
        new_label = 0
        mx = 0
        my = 0
    else:
        lat, lon = samples[sample_i]
        x, y, x_deg, y_deg = getXY(lat, lon, lat0, lon0, pix_deg)
        if sample_i == 0:
            mm_back[:] = 0
            mx = int(mm.shape[0] / 2 - 1)
            my = int(mm.shape[0] / 2 - 1)
            mx0_deg = x_deg - pix_deg * mx
            my0_deg = y_deg + pix_deg * my
            mm[:] = 0
        else:
            mm_back[:] |= mm[:]
            mx = int(round((x_deg - mx0_deg) / pix_deg))
            my = int(round((my0_deg - y_deg) / pix_deg))
    neighbors_i = 0
    dirNeighbors[0] = 255 # 255 is for uninitialized
    accNeighbors[0] = 0
    done = False
    skip = False
    while not done:
        reached_upper_ws = False
        if not skip:
            if getSubBass:
                this_acc = int(acc_tile[y, x])
                this_accDelta = acc - this_acc
                append_sample = False
                if this_accDelta >= accDelta and this_acc >= accDelta:
                    append_sample = True
                if in_latlon([y_deg - pix_deg / 2, x_deg + pix_deg / 2], sub_latlon, pix_deg):
                    rm_latlon([y_deg - pix_deg / 2, x_deg + pix_deg / 2], sub_latlon, pix_deg)
                    append_sample = True
                if append_sample:
                    acc = this_acc
                    sample_i += 1
                    if sample_i == samples.shape[0]:
                        samples_new = np.empty((samples.shape[0] * 2, 2), dtype=np.float32)
                        samples_new[:samples.shape[0], :] = samples
                        samples = samples_new
                        labels_new = np.empty((labels.shape[0] * 2, 3), dtype=np.int32)
                        labels_new[:labels.shape[0], :] = labels
                        labels = labels_new
                        lengths_new = np.empty(lengths.shape[0] * 2, dtype=np.float32)
                        lengths_new[:lengths.shape[0]] = lengths
                        lengths = lengths_new
                    samples[sample_i, :] = [y_deg - pix_deg / 2, x_deg + pix_deg / 2]
                    labels[sample_i, :] = [label_i, labels[label_i, 1] + 1, new_label]
                    lengths[sample_i] = get_length(y_deg - pix_deg / 2, x_deg + pix_deg / 2, lat0, lon0, samples[0, 0], samples[0, 1], dir_tile, pix_deg)
                    new_label = 0
                    label_i = sample_i
            else:
                if (mm_back[my, int(np.floor(mx / 8))] >> (mx % 8)) & 1 == 1: # we reached the upper subbasin
                    reached_upper_ws = True
                else:
                    mm[my, int(np.floor(mx / 8))] |= 1 << (mx % 8)
        nb = dirNeighbors[neighbors_i]
        if not reached_upper_ws and nb == 255:
            # find which pixels flow into this pixel
            nb = 0
            for i in range(8):
                if i < 4:
                    dir_back = 1 << (i + 4)
                else:
                    dir_back = 1 << (i - 4)
                dir_next, _, _, _, _, _, _ = go_get_dir(1 << i, dir_tile, x, y, mx, my, x_deg, y_deg, pix_deg)
                if dir_next == dir_back:
                    nb = nb | (1 << i)
            dirNeighbors[neighbors_i] = nb
            if getSubBass:
                accNeighbors[neighbors_i] = acc
        if reached_upper_ws or nb == 0: # no pixel flows into this pixel (this is a source), so we cannot go upper
            if neighbors_i == 0: # we are at the outlet and we processed every neighbor pixels, so we are done
                done = True
            else:
                passed_ws = False
                go_down = True
                while go_down:
                    _, x, y, mx, my, x_deg, y_deg = go_get_dir(dir_tile[y, x], dir_tile, x, y, mx, my, x_deg, y_deg, pix_deg)
                    if getSubBass:
                        if passed_ws: # we just passed a sub-basin
                            this_label = labels[label_i]
                            new_label = this_label[2] + 1
                            this_length = this_label[1]
                            while labels[label_i, 1] >= this_length:
                                label_i -= 1
                            passed_ws = False
                        # check if we are at a sub-basin outlet that we already passed
                        y_down, x_down = samples[label_i]
                        if (abs(y_down - (y_deg - pix_deg / 2)) < pix_deg / 4) and (abs(x_down - (x_deg + pix_deg / 2)) < pix_deg / 4):
                            passed_ws = True
                    neighbors_i -= 1
                    nb = dirNeighbors[neighbors_i]
                    i = find_first1(nb)
                    nb = nb & (255 - (1 << i))
                    if nb == 0:
                        if neighbors_i == 0:
                            go_down = False
                            done = True
                    else:
                        go_down = False
                        skip = True
                    dirNeighbors[neighbors_i] = nb
                acc = accNeighbors[neighbors_i]
        else: # go up
            skip = False
            neighbors_i += 1
            if neighbors_i == dirNeighbors.shape[0]:
                dirNeighbors_new = np.empty(dirNeighbors.shape[0] * 2, dtype = np.uint8)
                dirNeighbors_new[:dirNeighbors.shape[0]] = dirNeighbors
                dirNeighbors = dirNeighbors_new
                accNeighbors_new = np.empty(accNeighbors.shape[0] * 2, dtype = np.uint32)
                accNeighbors_new[:accNeighbors.shape[0]] = accNeighbors
                accNeighbors = accNeighbors_new
            dirNeighbors[neighbors_i] = 255
            accNeighbors[neighbors_i] = 0
            i = find_first1(nb)
            _, x, y, mx, my, x_deg, y_deg = go_get_dir(1 << i, dir_tile, x, y, mx, my, x_deg, y_deg, pix_deg)
        if done:
            ws_latlon = np.empty(2, dtype=np.float32)
            if getSubBass:
                sample_size = sample_i + 1
                # we need to reverse the samples (incremental delineation must go downstream)
                samples[:sample_size, :] = samples[sample_size-1::-1, :].copy()
                sample_i = 0
                ws_mask = np.empty((1, 1), dtype=np.uint8)
            else:
                sample_size = 0
                mm[:] &= ~mm_back[:]
                ws_mask, ws_latlon[0], ws_latlon[1] = get_bbox(mm, pix_deg, mx0_deg, my0_deg)
    return samples, labels, lengths, sample_size, mx0_deg, my0_deg, ws_mask, ws_latlon, dirNeighbors, accNeighbors

@jit(nopython=True)
def getXY(lat, lon, lat0, lon0, pix_deg):
    #lat = round(lat, 5)
    #lon = round(lon, 5)
    #x = int(np.floor((lon - lon0) / pix_deg))
    #y = int(np.floor((lat0 - lat) / pix_deg))
    x = int((lon - lon0) / pix_deg)
    y = int((lat0 - lat) / pix_deg)
    x_deg = lon0 + x * pix_deg
    y_deg = lat0 - y * pix_deg
    return x, y, x_deg, y_deg

def getTileInfo(lat, lon):
    pix_deg = 1 / 240 #0.004166666666667
    dir_url = None
    b = [5, 39, -119, -60]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/ca_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 14160, 8160
    b = [-56, 15, -93, -32]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/sa_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 14640, 17040
    b = [24, 61, -138, -52]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/na_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 20640, 8880
    b = [-35, 38, -19, 55]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/af_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 17760, 17520
    b = [12, 62, -14, 70]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/eu_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 20160, 12000
    b = [-56, -10, 112, 180]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/au_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 16320, 11040
    b = [-12, 61, 57, 180]
    if (dir_url is None) and (b[0] <= lat <= b[1]) and (b[2] <= lon <= b[3]):
        lat0, lon0 = b[1], b[2]
        dir_url = 'http://earlywarning.usgs.gov/hydrodata/sa_15s_zip_grid/as_dir_15s_grid.zip'
        acc_url = dir_url.replace('dir', 'acc')
        tile_width, tile_height = 29520, 17520
    if dir_url is None:
        print('Position not covered.')
        sys.exit()
    return tile_width, tile_height, dir_url, acc_url, lat0, lon0, pix_deg

def getTile(lat, lon, types):
    _, _, dir_url, acc_url, lat0, lon0, pix_deg = getTileInfo(lat, lon)
    x, y, x_deg, y_deg = getXY(lat, lon, lat0, lon0, pix_deg)

    url = {'dir': dir_url, 'acc': acc_url}
    tiles = {}
    for typ in types:
        this_url = url[typ]
        adffile = download(this_url)
        with rasterio.open(adffile) as src:
            data = src.read()
        tiles[typ] = data[0].astype({'dir': np.uint8, 'acc': np.uint32}[typ])
    return tiles

@jit(nopython=True)
def in_latlon(ll, ll_list, pix_deg):
    for i in range(ll_list.shape[0]):
        if ll_list[i, 0] > -900:
            if (abs(ll[0] - ll_list[i, 0]) < pix_deg / 4) and (abs(ll[1] - ll_list[i, 1]) < pix_deg / 4):
                return True
    return False

def is_empty_latlon(ll_list):
    for i in range(ll_list.shape[0]):
        if ll_list[i, 0] > -900:
            return False
    return True

@jit(nopython=True)
def rm_latlon(ll, ll_list, pix_deg):
    for i in range(ll_list.shape[0]):
        if ll_list[i, 0] > -900:
            if (abs(ll[0] - ll_list[i, 0]) < pix_deg / 4) and (abs(ll[1] - ll_list[i, 1]) < pix_deg / 4):
                ll_list[i] = [-999, -999]
                return

@jit(nopython=True)
def go_get_dir(dire, dir_tile, x, y, mx, my, x_deg, y_deg, pix_deg):
    for i in range(8):
        if (dire >> i) & 1 == 1:
            break
    dx = np.array([1, 1, 0, -1, -1, -1, 0, 1])[i]
    dy = np.array([0, 1, 1, 1, 0, -1, -1, -1])[i]
    return dir_tile[y + dy, x + dx], x + dx, y + dy, mx + dx, my + dy, x_deg + dx * pix_deg, y_deg - dy * pix_deg

@jit(nopython=True)
def find_first1(x):
    i = 0
    while (x & 1) == 0:
        x = x >> 1
        i += 1
    return i

@jit(nopython=True)
def get_bbox(mm, pix_deg, mx0_deg, my0_deg):
    going_down = True
    i = mm.shape[0] >> 1
    i0 = i
    i1 = i - 1
    done = False
    while not done:
        for j in range(mm.shape[1]):
            if mm[i, j] != 0:
                done = True
        if not done:
            if going_down:
                i0 += 1
                i = i1
            else:
                i1 -= 1
                i = i0
            going_down = not going_down
    if i > 0:
        i -= 1
    done = False
    while not done:
        done = True
        for j in range(mm.shape[1]):
            if mm[i, j] != 0:
                done = False
        if not done:
            i -= 1
            if i < 0:
                done = True
    i += 1

    x0 = mm.shape[1] * 8
    x1 = -1
    y0 = -1
    y1 = -1
    found_y = False
    done = False
    while not done:
        found_x = False
        for j in range(mm.shape[1]):
            if mm[i, j] != 0:
                found_x = True
                for k in range(8):
                    if (mm[i, j] >> k) & 1 == 1:
                        l = j * 8 + k
                        if x0 > l:
                            x0 = l
                        if x1 < l:
                            x1 = l
        if found_x:
            found_y = True
            y0 = i
            if y1 < 0:
                y1 = i
        if not found_x and found_y:
            done = True
        else:
            i += 1
            if i == mm.shape[0]:
                done = True
    y0 += 1
    x1 += 1
    mask = np.empty((y0 - y1, x1 - x0), dtype=np.uint8)
    for i in range(y1, y0):
        for j in range(x0, x1):
            mask[(i - y1), j - x0] = (mm[i, int(np.floor(j / 8))] >> (j % 8)) & 1
    return mask, my0_deg - pix_deg * y1, mx0_deg + pix_deg * x0
