import numpy as np
import xarray as xr
from skimage.measure import block_reduce
from shapely.geometry.polygon import Polygon
from shapely.ops import transform
import pyproj

def adjust_bbox(da, dims):
    coords = {}
    for k, v in dims.items():
        every = v[0]
        step = v[1] #da[k].values[1] - da[k].values[0]
        offset = step / 2
        dim0 = da[k].values[0] - offset
        dim1 = da[k].values[-1] + offset
        if step < 0: # decreasing
            dim0 = dim0 + every - dim0 % every
            dim1 = dim1 - dim1 % every
        else: # increasing
            dim0 = dim0 - dim0 % every
            dim1 = dim1 + every - dim1 % every
        coord0 = np.arange(dim0+offset, da[k].values[0]-offset, step)
        coord1 = da[k].values
        coord2 = np.arange(da[k].values[-1]+step, dim1, step)
        coord = np.hstack((coord0, coord1, coord2))
        coords[k] = coord
    return da.reindex(**coords).fillna(0)

# This code comes from https://github.com/pydata/xarray/issues/2525
# It should be replaced by coarsen (https://github.com/pydata/xarray/pull/2612)
def aggregate_da(da, agg_dims, suf='_agg'):
    input_core_dims = list(agg_dims)
    n_agg = len(input_core_dims)
    core_block_size = tuple([agg_dims[k] for k in input_core_dims])
    block_size = (da.ndim - n_agg)*(1,) + core_block_size
    output_core_dims = [dim + suf for dim in input_core_dims]
    output_sizes = {(dim + suf): da.shape[da.get_axis_num(dim)]//agg_dims[dim] for dim in input_core_dims}
    output_dtypes = da.dtype
    da_out = xr.apply_ufunc(block_reduce, da, kwargs={'block_size': block_size},
                            input_core_dims=[input_core_dims],
                            output_core_dims=[output_core_dims],
                            output_sizes=output_sizes,
                            output_dtypes=[output_dtypes],
                            dask='parallelized')
    for dim in input_core_dims:
        new_coord = block_reduce(da[dim].data, (agg_dims[dim],), func=np.mean)
        da_out.coords[dim + suf] = (dim + suf, new_coord)
    return da_out

# pixel area only depends on latitude (not longitude)
# we re-project WGS84 to cylindrical equal area
def pixel_area(pix_deg):
    project = lambda x, y: pyproj.transform(pyproj.Proj(init='epsg:4326'), pyproj.Proj(proj='cea'), x, y)
    offset = pix_deg / 2
    lts = np.arange(90-offset, -90, -pix_deg)
    area = np.empty_like(lts)
    lon = 0
    for y, lat in enumerate(lts):
        pixel1 = Polygon([(lon - offset, lat + offset), (lon + offset, lat + offset), (lon + offset, lat - offset), (lon - offset, lat - offset)])
        pixel2 = transform(project, pixel1)
        area[y] = pixel2.area
    return xr.DataArray(area, coords=[lts], dims=['lat'])
