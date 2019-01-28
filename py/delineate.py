import numpy as np
import sys
import os
_ = os.path.dirname(os.path.abspath(__file__))
sys.path.append(_ + '/cy')
from cdelineate import cdelineate

def delineate(lat, lon, _sub_latlon=[], accDelta=np.inf, label=None):
    pix_deg = 1 / 1200
    lat = (lat // pix_deg) * pix_deg + pix_deg
    lon = (lon // pix_deg) * pix_deg
    getSubBass = True
    sample_i = 0
    samples = np.empty((1024, 2), dtype=np.float64)
    lengths = np.empty(1024, dtype=np.float64)
    labels = np.empty((1024, 3), dtype=np.int32)
    dirNeighbors = np.empty(1024, dtype=np.uint8)
    accNeighbors = np.empty(1024, dtype=np.float64)
    ws_latlon = np.empty(2, dtype=np.float64)
    # output mask ->
    mxw = 8192 # bytes
    myw = mxw * 8 # bits
    mm = np.empty((myw, mxw), dtype=np.uint8)
    mm_back = np.empty((myw, mxw), dtype=np.uint8)
    mx0_deg = 0
    my0_deg = 0
    # <- output mask

    simple_delineation = False
    if len(_sub_latlon) == 0:
        sub_latlon = np.empty((1, 2), dtype=np.float64)
        sub_latlon[0, :] = [lat, lon]
        if not np.isfinite(accDelta):
            simple_delineation = True
    else:
        sub_latlon = np.empty((len(_sub_latlon), 2), dtype=np.float64)
        sub_latlon[:, :] = _sub_latlon
    tile_deg = 5
    tile_size = int(round(tile_deg / pix_deg))
    if simple_delineation:
        sample_size = 1
        samples[0] = [lat, lon]
    else:
        #print('Getting bassin partition...')
        samples, labels, lengths, sample_size, mx0_deg, my0_deg, ws_mask, ws_latlon, dirNeighbors, accNeighbors = cdelineate(lat, lon, getSubBass, sample_i, samples, labels, lengths, pix_deg, tile_deg, accDelta, sub_latlon, mm, mm_back, mx0_deg, my0_deg, dirNeighbors, accNeighbors)
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
        _, _, _, _, mx0_deg, my0_deg, ws_mask, ws_latlon, dirNeighbors, accNeighbors = cdelineate(lat, lon, getSubBass, sample_i, samples, labels, lengths, pix_deg, tile_deg, accDelta, sub_latlon, mm, mm_back, mx0_deg, my0_deg, dirNeighbors, accNeighbors)
        mask.append(ws_mask)
        latlon.append(ws_latlon)
        lat_min = min(lat_min, ws_latlon[0] - ws_mask.shape[0] * pix_deg)
        lat_max = max(lat_max, ws_latlon[0])
        lon_min = min(lon_min, ws_latlon[1])
        lon_max = max(lon_max, ws_latlon[1] + ws_mask.shape[1] * pix_deg)
    ws = {}
    if (lat_min == lat_max) and (lon_min == lon_max):
        ws['bbox'] = [lat_max, lon_min, mask[0].shape[0], mask[0].shape[1]]
    else:
        ws['bbox'] = [lat_max, lon_min, int(round((lat_max - lat_min) / pix_deg)), int(round((lon_max - lon_min) / pix_deg))]
    ws['outlet'] = samples[sample_size - 1::-1]
    ws['length'] = lengths[:sample_size]
    ws['mask'] = mask[::-1]
    ws['latlon'] = np.empty((sample_size, 2), dtype=np.float64)
    ws['latlon'][:, :] = latlon[::-1]
    # label re-construction:
    ws['label'] = []
    for sample_i in range(sample_size):
        if sample_i == 0: # outlet subbassin
            ws['label'].append('0')
        else:
            i = labels[sample_i][0]
            ws['label'].append(ws['label'][i] + ',' + str(labels[sample_i][2]))
    return ws

def is_empty_latlon(ll_list):
    for i in range(ll_list.shape[0]):
        if ll_list[i, 0] > -900:
            return False
    return True
