addLayer = (layer, name, zIndex) ->
    layer.setZIndex(zIndex).addTo(map)
    layer.setOpacity(0.5)
    link = document.createElement('a')
    link.href = '#'
    link.className = 'active'
    link.innerHTML = name
    link.onclick = (e) ->
        e.preventDefault()
        e.stopPropagation()
        if map.hasLayer(layer)
            map.removeLayer(layer)
            this.className = ''
        else
            map.addLayer(layer)
            this.className = 'active'
    layers.appendChild(link)

accDelta = 1000
pix_deg = 0.0083333333333
dir_tiles = 0
acc_tiles = 0
x_deg = 0
y_deg = 0
x = 0
y = 0
# output mask ->
mxw = 1500 # bytes
myw = mxw * 8 # bits
mx = 0
my = 0
mm = new Uint8Array(mxw * myw)
mm_back = new Uint8Array(mxw * myw)
mx0_deg = 0
my0_deg = 0
nbline_max = 65536
mx0 = new Uint16Array(nbline_max)
mx1 = new Uint16Array(nbline_max)
my0 = new Uint16Array(nbline_max)
my1 = new Uint16Array(nbline_max)
# <- output mask
state = 0
neighbors_memsize = 1024
neighbors_i = 0
dirNeighbors = new Uint8Array(neighbors_memsize)
accNeighbors = new Int32Array(neighbors_memsize)
tile_width = 1200
polygons = 0
polyLayers = 0
pol_i = 0
pix_i = 0
pack_size = 10
watershed = 0
watershedLayer = 0
samples = []
sample_i = 0
sample_nb = 50
sample_cb = 0
watersheds = 0
spin_opts = {
, lines: 13 # The number of lines to draw
, length: 28 # The length of each line
, width: 14 # The line thickness
, radius: 42 # The radius of the inner circle
, scale: 1 # Scales overall size of the spinner
, corners: 1 # Corner roundness (0..1)
, color: '#6BC65F' # #rgb or #rrggbb or array of colors
, opacity: 0.25 # Opacity of the lines
, rotate: 0 # The rotation offset
, direction: 1 # 1: clockwise, -1: counterclockwise
, speed: 1 # Rounds per second
, trail: 60 # Afterglow percentage
, fps: 20 # Frames per second when using setTimeout() as a fallback for CSS
, zIndex: 2e9 # The z-index (defaults to 2000000000)
, className: 'spinner' # The CSS class to assign to the spinner
, top: '50%' # Top position relative to parent
, left: '50%' # Left position relative to parent
, shadow: false # Whether to render a shadow
, hwaccel: false # Whether to use hardware acceleration
, position: 'absolute' # Element positioning
}
spin_target = document.getElementById('spin')
spinner = new Spinner(spin_opts)

runGen = (g, p) ->
    it = g(p)
    res = 0
    val = 0
    do iterate = (val) ->
        ret = it.next(val)
        if ret.done
            res = ret.value
        else
            ret.value.then(iterate)
    return res

polygonize = ->
    console.log 'polygonize'
    line_i = 0
    pix_j = 0
    done = false
    i0 = myw / 2 - 1
    ix = i0
    iy = i0
    size = 1
    going = 1
    while not done
       this_pix = false
       if (mm[iy * mxw + Math.floor(ix / 8)] >> (ix % 8)) & 1 == 1
           this_pix = true
           pix_j += 1
       if ix != 0
           pix_l = false
           if (mm[iy * mxw + Math.floor((ix - 1) / 8)] >> ((ix - 1) % 8)) & 1 == 1
               pix_l = true
       if ix != myw - 1
           pix_r = false
           if (mm[iy * mxw + Math.floor((ix + 1) / 8)] >> ((ix + 1) % 8)) & 1 == 1
               pix_r = true
       if iy != 0
           pix_u = false
           if (mm[(iy - 1) * mxw + Math.floor(ix / 8)] >> (ix % 8)) & 1 == 1
               pix_u = true
       if iy != myw - 1
           pix_d = false
           if (mm[(iy + 1) * mxw + Math.floor(ix / 8)] >> (ix % 8)) & 1 == 1
               pix_d = true
       if ix != 0 and iy != 0
           pix_ul = false
           if (mm[(iy - 1) * mxw + Math.floor((ix - 1) / 8)] >> ((ix - 1) % 8)) & 1 == 1
               pix_ul = true
       if ix != myw - 1 and iy != 0
           pix_ur = false
           if (mm[(iy - 1) * mxw + Math.floor((ix + 1) / 8)] >> ((ix + 1) % 8)) & 1 == 1
               pix_ur = true
       if ix != 0 and iy != myw - 1
           pix_ll = false
           if (mm[(iy + 1) * mxw + Math.floor((ix - 1) / 8)] >> ((ix - 1) % 8)) & 1 == 1
               pix_ll = true
       if ix != myw - 1 and iy != myw - 1
           pix_lr = false
           if (mm[(iy + 1) * mxw + Math.floor((ix + 1) / 8)] >> ((ix + 1) % 8)) & 1 == 1
               pix_lr = true
       # lower right:
       if ix != myw - 1 and iy != myw - 1
           if this_pix and not pix_r and pix_lr and not pix_ur
               mx0[line_i] = 2 * ix + 2
               mx1[line_i] = 2 * ix + 2 + 1
               my0[line_i] = 2 * iy
               my1[line_i] = 2 * iy + 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
           if this_pix and not pix_d and pix_lr and not pix_ll
               mx0[line_i] = 2 * ix
               mx1[line_i] = 2 * ix + 1
               my0[line_i] = 2 * iy + 2
               my1[line_i] = 2 * iy + 2 + 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
       # lower left:
       if ix != 0 and iy != myw - 1
           if this_pix and not pix_l and pix_ll and not pix_ul
               mx0[line_i] = 2 * ix
               mx1[line_i] = 2 * ix - 1
               my0[line_i] = 2 * iy
               my1[line_i] = 2 * iy + 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
           if this_pix and not pix_d and pix_ll and not pix_lr
               mx0[line_i] = 2 * ix + 2
               mx1[line_i] = 2 * ix + 1
               my0[line_i] = 2 * iy + 2
               my1[line_i] = 2 * iy + 2 + 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
       # upper left:
       if ix != 0 and iy != 0
           if this_pix and not pix_l and pix_ul and not pix_ll
               mx0[line_i] = 2 * ix
               mx1[line_i] = 2 * ix - 1
               my0[line_i] = 2 * iy + 2
               my1[line_i] = 2 * iy + 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
           if this_pix and not pix_u and pix_ul and not pix_ur
               mx0[line_i] = 2 * ix + 2
               mx1[line_i] = 2 * ix + 1
               my0[line_i] = 2 * iy
               my1[line_i] = 2 * iy - 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
       # upper right:
       if ix != myw - 1 and iy != 0
           if this_pix and not pix_u and pix_ur and not pix_ul
               mx0[line_i] = 2 * ix
               mx1[line_i] = 2 * ix + 1
               my0[line_i] = 2 * iy
               my1[line_i] = 2 * iy - 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
           if this_pix and not pix_r and pix_ur and not pix_lr
               mx0[line_i] = 2 * ix + 2
               mx1[line_i] = 2 * ix + 2 + 1
               my0[line_i] = 2 * iy + 2
               my1[line_i] = 2 * iy + 1
               line_i += 1
               if line_i == nbline_max
                   extend_lineBuffer()
       # left:
       if (ix != 0 and this_pix and not pix_l and not pix_ul and not pix_ll) or (ix == 0 and this_pix)
           mx0[line_i] = 2 * ix
           mx1[line_i] = 2 * ix
           my0[line_i] = 2 * iy
           my1[line_i] = 2 * iy + 2
           line_i += 1
           if line_i == nbline_max
               extend_lineBuffer()
       # right:
       if (ix != myw - 1 and this_pix and not pix_r and not pix_ur and not pix_lr) or (ix == myw - 1 and this_pix)
           mx0[line_i] = 2 * ix + 2
           mx1[line_i] = 2 * ix + 2
           my0[line_i] = 2 * iy
           my1[line_i] = 2 * iy + 2
           line_i += 1
           if line_i == nbline_max
               extend_lineBuffer()
       # up:
       if (iy != 0 and this_pix and not pix_u and not pix_ul and not pix_ur) or (iy == 0 and this_pix)
           mx0[line_i] = 2 * ix
           mx1[line_i] = 2 * ix + 2
           my0[line_i] = 2 * iy
           my1[line_i] = 2 * iy
           line_i += 1
           if line_i == nbline_max
               extend_lineBuffer()
       # down:
       if (iy != myw - 1 and this_pix and not pix_d and not pix_ll and not pix_lr) or (iy == myw - 1 and this_pix)
           mx0[line_i] = 2 * ix
           mx1[line_i] = 2 * ix + 2
           my0[line_i] = 2 * iy + 2
           my1[line_i] = 2 * iy + 2
           line_i += 1
           if line_i == nbline_max
               extend_lineBuffer()
        if pix_j == pix_i
            done = true
        else
            if going == 1
                ix += 1
                if ix - i0 == size
                    going = 2
            else if going == 2
                iy += 1
                if iy - i0 == size
                    going = 3
            else if going == 3
                if ix == 0
                    done = true
                else
                    ix -= 1
                    if i0 - ix == size
                        going = 4
            else if going == 4
                iy -= 1
                if i0 - iy == size
                    going = 1
                    size += 1
    all_pol_done = false
    polygon = []
    while not all_pol_done
        done = false
        i = 0
        while not done
            if mx0[i] != nbline_max - 1
                done = true
                #console.log 'done'
            else
                i += 1
                if i == line_i
                    done = true
                    all_pol_done = true
                    #console.log 'all_pol_done'
        if not all_pol_done
            polygon.push([[mx0[i], my0[i]], [mx1[i], my1[i]]])
            last_polygon = polygon[polygon.length - 1]
            mx0[i] = nbline_max - 1
            mx1[i] = nbline_max - 1
            pol_done = false
            while not pol_done
                search_done = false
                found = false
                i = 0
                this_x = last_polygon[last_polygon.length - 1][0]
                this_y = last_polygon[last_polygon.length - 1][1]
                while not search_done
                    if mx0[i] != nbline_max - 1 and mx0[i] == this_x and my0[i] == this_y
                        found = true
                        found0 = true
                        search_done = true
                        #console.log 'found ;-)'
                    else if mx1[i] != nbline_max - 1 and mx1[i] == this_x and my1[i] == this_y
                        found = true
                        found0 = false
                        search_done = true
                        #console.log 'found ;-)'
                    else
                        i += 1
                        if i == line_i
                            search_done = true
                            #console.log 'not found!'
                if found
                    if found0
                        last_polygon.push([mx1[i], my1[i]])
                    else
                        last_polygon.push([mx0[i], my0[i]])
                    mx0[i] = nbline_max - 1
                    mx1[i] = nbline_max - 1
                if last_polygon[last_polygon.length - 1][0] == last_polygon[0][0] and last_polygon[last_polygon.length - 1][1] == last_polygon[0][1]
                    pol_done = true
            for i in [0..last_polygon.length - 1]
                last_polygon[i][0] = mx0_deg + last_polygon[i][0] * pix_deg / 2
                last_polygon[i][1] = my0_deg - last_polygon[i][1] * pix_deg / 2
    for i in [0..polygon.length - 1]
        polygon[i] = turf.polygon([polygon[i]])
    console.log 'polygon.length = ', polygon.length
    watershed = polygon[0]
    for i in [0..polygon.length - 1]
        for j in [0..polygon.length - 1]
            if polygon[i] != 0 and polygon[j] != 0
                intersect = turf.intersect(polygon[i], polygon[j])
                if intersect?
                    erase = turf.erase(polygon[i], polygon[j])
                    if erase?
                        polygon[i] = erase
                        polygon[j] = 0
                        watershed = erase
                    else
                        erase = turf.erase(polygon[j], polygon[i])
                        if erase?
                            polygon[i] = 0
                            polygon[j] = erase
                            watershed = erase
    return

extend_lineBuffer = ->
    console.log 'extend_lineBuffer'
    new_size = nbline_max * 2
    new_mx0 = new Uint16Array(new_size)
    new_my0 = new Uint16Array(new_size)
    new_mx1 = new Uint16Array(new_size)
    new_my1 = new Uint16Array(new_size)
    for i in [0..nbline_max - 1]
        new_mx0[i] = mx0[i]
        new_my0[i] = my0[i]
        new_mx1[i] = mx1[i]
        new_my1[i] = my1[i]
    mx0 = new_mx0
    my0 = new_my0
    mx1 = new_mx1
    my1 = new_my1
    nbline_max = new_size

getTile = (url, type, cb) ->
    console.log 'Downloading ' + url
    req = new XMLHttpRequest()
    req.open 'GET', url, true
    req.responseType = 'arraybuffer'
    req.onload = ->
        arrayBuffer = req.response
        if arrayBuffer
            console.log 'Done!'
            if type == 'dir'
                cb(new Uint8Array(arrayBuffer))
            else if type == 'acc'
                cb(new Int32Array(arrayBuffer))
    req.send(null)
    return

do_delineate = (p) ->
    latlng = p
    if state == 'wsOnStr'
        url = get_url(samples[sample_i][0], samples[sample_i][1], true)
    else
        url = get_url(latlng[0], latlng[1], true)
    if state == 'watershed' or state == 'subWs'
        spinner.spin(spin_target)
    if state == 'wsOnStr'
        if sample_i == 0
            for i in [0..mxw * myw - 1]
                mm_back[i] = 0
        else
            for i in [0..mxw * myw - 1]
                mm_back[i] = mm[i]
    this_outlet = turf.point([x_deg + pix_deg / 2, y_deg - pix_deg / 2])
    if state == 'wsOnStr' and sample_i > 0
        mx = Math.round((x_deg - mx0_deg) / pix_deg)
        my = Math.round((my0_deg - y_deg) / pix_deg)
    else
        mx = myw / 2 - 1
        my = myw / 2 - 1
        mx0_deg = x_deg - pix_deg * mx
        my0_deg = y_deg + pix_deg * my
        for i in [0..mxw * myw - 1]
            mm[i] = 0
    pix_i = 0
    neighbors_i = 0
    dirNeighbors[0] = 255 # 255 is for uninitialized
    accNeighbors[0] = 0
    dir_tiles = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    acc_tiles = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    dir_tiles[0] = yield p_getTile(url['dir'], 'dir')
    if state == 'subWs'
        acc_tiles[0] = yield p_getTile(url['acc'], 'acc')
        acc = acc_tiles[0][y * tile_width + x]
    done = false
    skip = false
    pol_i = 0
    polygons = []
    polyLayers = []
    if state == 'subWs'
        this_subOutlet = turf.polygon([[[x_deg, y_deg], [x_deg + pix_deg, y_deg], [x_deg + pix_deg, y_deg - pix_deg], [x_deg, y_deg - pix_deg], [x_deg, y_deg]]])
        this_subOutlet.properties = {
            "fill": "#bd0026",
            "stroke": "#bd0026",
            "stroke-width": 3
        }
        subOutletLayer = L.mapbox.featureLayer(this_subOutlet).addTo(map)
    while !done
        reached_upper_ws = false
        if !skip
            if state == 'wsOnStr' and (mm[my * mxw + Math.floor(mx / 8)] >> (mx % 8)) & 1 == 1 # we reached the upper sub-watershed
                reached_upper_ws = true
            else
                mm[my * mxw + Math.floor(mx / 8)] |= 1 << (mx % 8)
                pix_i += 1
                if state == 'subWs'
                    this_acc = acc_tiles[0][y * tile_width + x]
                    this_accDelta = acc - this_acc
                    if this_accDelta >= accDelta and this_acc >= accDelta
                        acc = this_acc
                        this_subOutlet = turf.polygon([[[x_deg, y_deg], [x_deg + pix_deg, y_deg], [x_deg + pix_deg, y_deg - pix_deg], [x_deg, y_deg - pix_deg], [x_deg, y_deg]]])
                        this_subOutlet.properties = {
                            "fill": "#bd0026",
                            "stroke": "#bd0026",
                            "stroke-width": 3
                        }
                        subOutletLayer = L.mapbox.featureLayer(this_subOutlet).addTo(map)
        nb = dirNeighbors[neighbors_i]
        if !reached_upper_ws and nb == 255
            # find which pixels flow into this pixel
            nb = 0
            for i in [0..7]
                if i < 4
                    dir_back = 1 << (i + 4)
                else
                    dir_back = 1 << (i - 4)
                ret = go_get_dir(1 << i, false, true)
                if ret['url'] != 0 # we need to download a tile
                    dir_tile = yield p_getTile(ret['url']['dir'], 'dir')
                    if state == 'subWs'
                        acc_tile = yield p_getTile(ret['url']['acc'], 'acc')
                    ret = go_get_dir(1 << i, false, false, dir_tile, acc_tile)
                dir_next = ret['dir']
                if dir_next == dir_back
                    nb = nb | (1 << i)
            dirNeighbors[neighbors_i] = nb
            accNeighbors[neighbors_i] = acc
        if reached_upper_ws or nb == 0 # no pixel flows into this pixel (this is a source), so we cannot go upper
            if neighbors_i == 0 # we are at the outlet and we processed every neighbor pixels, so we are done
                done = true
            else
                go_down = true
                while go_down
                    ret = go_get_dir(dir_tiles[0][y * tile_width + x], true, true)
                    if ret['url'] != 0 # we need to download a tile
                        dir_tile = yield p_getTile(ret['url']['dir'], 'dir')
                        if state == 'subWs'
                            acc_tile = yield p_getTile(ret['url']['acc'], 'acc')
                        ret = go_get_dir(dir_tiles[0][y * tile_width + x], true, false, dir_tile, acc_tile)
                    neighbors_i -= 1
                    nb = dirNeighbors[neighbors_i]
                    i = find1(nb)
                    nb = nb & (255 - (1 << i))
                    if nb == 0
                        if neighbors_i == 0
                            go_down = false
                            done = true
                    else
                        go_down = false
                        skip = true
                    dirNeighbors[neighbors_i] = nb
                acc = accNeighbors[neighbors_i]
        else # go up
            skip = false
            neighbors_i += 1
            if neighbors_i == neighbors_memsize
                console.log 'Extending neighbors'
                neighbors_new = new Uint8Array(neighbors_memsize * 2)
                for i in [0..neighbors_memsize - 1]
                    neighbors_new[i] = dirNeighbors[i]
                dirNeighbors = neighbors_new
                neighbors_new = new Int32Array(neighbors_memsize * 2)
                for i in [0..neighbors_memsize - 1]
                    neighbors_new[i] = accNeighbors[i]
                accNeighbors = neighbors_new
                neighbors_memsize *= 2
            dirNeighbors[neighbors_i] = 255
            accNeighbors[neighbors_i] = 0
            i = find1(nb)
            ret = go_get_dir(1 << i, true, true)
            if ret['url'] != 0 # we need to download a tile
                dir_tile = yield p_getTile(ret['url']['dir'], 'dir')
                if state == 'subWs'
                    acc_tile = yield p_getTile(ret['url']['acc'], 'acc')
                ret = go_get_dir(1 << i, true, false, dir_tile, acc_tile)
        if done
            if state == 'watershed'
                spinner.stop()
            else if state == 'wsOnStr'
                for i in [0..mxw * myw - 1]
                    mm[i] = mm[i] & ~mm_back[i]
            polygonize()
            watershed.properties = {
                "fill": "#6BC65F",
                "stroke": "#6BC65F",
                "stroke-width": 1
            }
            if state == 'subWs'
                spinner.stop()
            if state == 'wsOnStr'
                if sample_i == 0
                    watersheds = []
                else
                    map.removeLayer(watershedLayer)
                watersheds.push(watershed)
                sample_i += 1
                if sample_i < samples.length
                    watershedLayer = L.mapbox.featureLayer(watershed).addTo(map)
                    runGen(do_delineate)
                else
                    spinner.stop()
                    watersheds = turf.featurecollection(watersheds)
                    watershedLayer = L.mapbox.featureLayer(watersheds).addTo(map)
                    watershedLayer.on('click', (e) ->
                        url = 'data:text/json;charset=utf8,' + encodeURIComponent(JSON.stringify(watersheds))
                        link = document.createElement('a')
                        link.href = url
                        link.download = 'watershed.json'
                        link.click()
                        alert('Watershed GeoJSON downloaded')
                    )
            else if state == 'watershed'
                    watershedLayer = L.mapbox.featureLayer(watershed).addTo(map)
                    outletLayer = L.mapbox.featureLayer(this_outlet).addTo(map)
                    outletLayer.bindPopup('<strong>Area</strong> = ' + round(turf.area(watershed) / 1e6, 1).toString() + ' km²').addTo(map)
                    watershedLayer.on('mouseover', (e) -> outletLayer.openPopup())
                    watershedLayer.on('click', (e) ->
                        url = 'data:text/json;charset=utf8,' + encodeURIComponent(JSON.stringify(watershed.geometry))
                        link = document.createElement('a')
                        link.href = url
                        link.download = 'watershed.json'
                        link.click()
                        alert('Watershed GeoJSON downloaded')
                    )
    return

do_stream = (p) ->
    console.log 'do_stream'
    console.log 'state = ' + state
    latlng = p
    url = get_url(latlng[0], latlng[1], true)
    source = turf.point([x_deg + pix_deg / 2, y_deg - pix_deg / 2])
    dir_tiles = [0, 0, 0, 0, 0, 0, 0, 0, 0]
    dir_tiles[0] = yield p_getTile(url['dir'], 'dir')
    stream = [[x_deg + pix_deg / 2, y_deg - pix_deg / 2]]
    done = false
    while !done
        x_deg_keep = x_deg
        y_deg_keep = y_deg
        ret = go_get_dir(dir_tiles[0][y * tile_width + x], true, true)
        if ret['url'] != 0
            dir_tile = yield p_getTile(ret['url']['dir'], 'dir')
            ret = go_get_dir(dir_tiles[0][y * tile_width + x], true, false, dir_tile)
        if x_deg == x_deg_keep and y_deg == y_deg_keep
            done = true
        else
            stream.push([x_deg + pix_deg / 2, y_deg - pix_deg / 2])
    stream = turf.linestring(stream)
    if state == 'stream'
        spinner.stop()
    stream.properties = {
        "fill": "#6BC65F",
        "stroke": "#6BC65F",
        "stroke-width": 3
    }
    streamLayer = L.mapbox.featureLayer(stream).addTo(map)
    if state == 'stream'
        sourceLayer = L.mapbox.featureLayer(source).addTo(map)
        sourceLayer.bindPopup('<strong>Length</strong> = ' + round(turf.lineDistance(stream, 'kilometers'), 1).toString() + ' km').addTo(map)
        streamLayer.on('mouseover', (e) -> sourceLayer.openPopup())
        streamLayer.on('click', (e) ->
            url = 'data:text/json;charset=utf8,' + encodeURIComponent(JSON.stringify(stream.geometry))
            link = document.createElement('a')
            link.href = url
            link.download = 'stream.json'
            link.click()
            alert('Stream GeoJSON downloaded')
    )
    if state == 'wsOnStr'
        samples = []
        i = 0
        done = false
        while !done
            i += sample_nb
            if i < stream.geometry.coordinates.length
                samples.push([stream.geometry.coordinates[i][1], stream.geometry.coordinates[i][0]])
            else
                done = true
        sample_i = 0
        runGen(do_delineate)
    return

find1 = (a) ->
    i = 0
    while (a & 1) == 0
        a = a >> 1
        i += 1
    return i

go_get_dir = (dir, go, first, dir_tile, acc_tile) ->
    ret = []
    ret['url'] = 0
    x_next = x
    y_next = y
    mx_next = mx
    my_next = my
    x_deg_next = x_deg
    y_deg_next = y_deg
    tile_i = 0
    if dir == 1
        x_next += 1
    else if dir == 2
        x_next += 1
        y_next += 1
    else if dir == 4
        y_next += 1
    else if dir == 8
        x_next -= 1
        y_next += 1
    else if dir == 16
        x_next -= 1
    else if dir == 32
        x_next -= 1
        y_next -= 1
    else if dir == 64
        y_next -= 1
    else if dir == 128
        x_next += 1
        y_next -= 1
    x_deg_next += (x_next - x) * pix_deg
    y_deg_next -= (y_next - y) * pix_deg
    mx_next += x_next - x
    my_next += y_next - y
    if x_next == -1 and y_next == -1
        x_next = tile_width - 1
        y_next = tile_width - 1
        if go
            if dir_tiles[6] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[6] = dir_tile
                    acc_tiles[6] = acc_tile
            if ret['url'] == 0
                dir_tiles[1] = dir_tiles[7]
                dir_tiles[2] = dir_tiles[0]
                dir_tiles[3] = dir_tiles[5]
                dir_tiles[0] = dir_tiles[6]
                dir_tiles[4] = 0
                dir_tiles[5] = 0
                dir_tiles[6] = 0
                dir_tiles[7] = 0
                dir_tiles[8] = 0
                acc_tiles[1] = acc_tiles[7]
                acc_tiles[2] = acc_tiles[0]
                acc_tiles[3] = acc_tiles[5]
                acc_tiles[0] = acc_tiles[6]
                acc_tiles[4] = 0
                acc_tiles[5] = 0
                acc_tiles[6] = 0
                acc_tiles[7] = 0
                acc_tiles[8] = 0
        else
            tile_i = 6
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if x_next == tile_width and y_next == -1
        x_next = 0
        y_next = tile_width - 1
        if go
            if dir_tiles[8] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[8] = dir_tile
                    acc_tiles[8] = acc_tile
            if ret['url'] == 0
                dir_tiles[3] = dir_tiles[1]
                dir_tiles[4] = dir_tiles[0]
                dir_tiles[5] = dir_tiles[7]
                dir_tiles[0] = dir_tiles[8]
                dir_tiles[2] = 0
                dir_tiles[1] = 0
                dir_tiles[8] = 0
                dir_tiles[7] = 0
                dir_tiles[6] = 0
                acc_tiles[3] = acc_tiles[1]
                acc_tiles[4] = acc_tiles[0]
                acc_tiles[5] = acc_tiles[7]
                acc_tiles[0] = acc_tiles[8]
                acc_tiles[2] = 0
                acc_tiles[1] = 0
                acc_tiles[8] = 0
                acc_tiles[7] = 0
                acc_tiles[6] = 0
        else
            tile_i = 8
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if x_next == tile_width and y_next == tile_width
        x_next = 0
        y_next = 0
        if go
            if dir_tiles[2] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[2] = dir_tile
                    acc_tiles[2] = acc_tile
            if ret['url'] == 0
                dir_tiles[5] = dir_tiles[3]
                dir_tiles[6] = dir_tiles[0]
                dir_tiles[7] = dir_tiles[1]
                dir_tiles[0] = dir_tiles[2]
                dir_tiles[4] = 0
                dir_tiles[3] = 0
                dir_tiles[2] = 0
                dir_tiles[1] = 0
                dir_tiles[8] = 0
                acc_tiles[5] = acc_tiles[3]
                acc_tiles[6] = acc_tiles[0]
                acc_tiles[7] = acc_tiles[1]
                acc_tiles[0] = acc_tiles[2]
                acc_tiles[4] = 0
                acc_tiles[3] = 0
                acc_tiles[2] = 0
                acc_tiles[1] = 0
                acc_tiles[8] = 0
        else
            tile_i = 2
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if x_next == -1 and y_next == tile_width
        x_next = tile_width - 1
        y_next = 0
        if go
            if dir_tiles[4] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[4] = dir_tile
                    acc_tiles[4] = acc_tile
            if ret['url'] == 0
                dir_tiles[7] = dir_tiles[5]
                dir_tiles[8] = dir_tiles[0]
                dir_tiles[1] = dir_tiles[3]
                dir_tiles[0] = dir_tiles[4]
                dir_tiles[6] = 0
                dir_tiles[5] = 0
                dir_tiles[4] = 0
                dir_tiles[3] = 0
                dir_tiles[2] = 0
                acc_tiles[7] = acc_tiles[5]
                acc_tiles[8] = acc_tiles[0]
                acc_tiles[1] = acc_tiles[3]
                acc_tiles[0] = acc_tiles[4]
                acc_tiles[6] = 0
                acc_tiles[5] = 0
                acc_tiles[4] = 0
                acc_tiles[3] = 0
                acc_tiles[2] = 0
        else
            tile_i = 4
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if y_next == -1
        y_next = tile_width - 1
        if go
            if dir_tiles[7] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[7] = dir_tile
                    acc_tiles[7] = acc_tile
            if ret['url'] == 0
                dir_tiles[4] = dir_tiles[5]
                dir_tiles[3] = dir_tiles[0]
                dir_tiles[2] = dir_tiles[1]
                dir_tiles[5] = dir_tiles[6]
                dir_tiles[0] = dir_tiles[7]
                dir_tiles[1] = dir_tiles[8]
                dir_tiles[6] = 0
                dir_tiles[7] = 0
                dir_tiles[8] = 0
                acc_tiles[4] = acc_tiles[5]
                acc_tiles[3] = acc_tiles[0]
                acc_tiles[2] = acc_tiles[1]
                acc_tiles[5] = acc_tiles[6]
                acc_tiles[0] = acc_tiles[7]
                acc_tiles[1] = acc_tiles[8]
                acc_tiles[6] = 0
                acc_tiles[7] = 0
                acc_tiles[8] = 0
        else
            tile_i = 7
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if x_next == tile_width
        x_next = 0
        if go
            if dir_tiles[1] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[1] = dir_tile
                    acc_tiles[1] = acc_tile
            if ret['url'] == 0
                dir_tiles[6] = dir_tiles[7]
                dir_tiles[5] = dir_tiles[0]
                dir_tiles[4] = dir_tiles[3]
                dir_tiles[7] = dir_tiles[8]
                dir_tiles[0] = dir_tiles[1]
                dir_tiles[3] = dir_tiles[2]
                dir_tiles[8] = 0
                dir_tiles[1] = 0
                dir_tiles[2] = 0
                acc_tiles[6] = acc_tiles[7]
                acc_tiles[5] = acc_tiles[0]
                acc_tiles[4] = acc_tiles[3]
                acc_tiles[7] = acc_tiles[8]
                acc_tiles[0] = acc_tiles[1]
                acc_tiles[3] = acc_tiles[2]
                acc_tiles[8] = 0
                acc_tiles[1] = 0
                acc_tiles[2] = 0
        else
            tile_i = 1
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if y_next == tile_width
        y_next = 0
        if go
            if dir_tiles[3] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[3] = dir_tile
                    acc_tiles[3] = acc_tile
            if ret['url'] == 0
                dir_tiles[6] = dir_tiles[5]
                dir_tiles[7] = dir_tiles[0]
                dir_tiles[8] = dir_tiles[1]
                dir_tiles[5] = dir_tiles[4]
                dir_tiles[0] = dir_tiles[3]
                dir_tiles[1] = dir_tiles[2]
                dir_tiles[4] = 0
                dir_tiles[3] = 0
                dir_tiles[2] = 0
                acc_tiles[6] = acc_tiles[5]
                acc_tiles[7] = acc_tiles[0]
                acc_tiles[8] = acc_tiles[1]
                acc_tiles[5] = acc_tiles[4]
                acc_tiles[0] = acc_tiles[3]
                acc_tiles[1] = acc_tiles[2]
                acc_tiles[4] = 0
                acc_tiles[3] = 0
                acc_tiles[2] = 0
        else
            tile_i = 3
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    else if x_next == -1
        x_next = tile_width - 1
        if go
            if dir_tiles[5] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[5] = dir_tile
                    acc_tiles[5] = acc_tile
            if ret['url'] == 0
                dir_tiles[8] = dir_tiles[7]
                dir_tiles[1] = dir_tiles[0]
                dir_tiles[2] = dir_tiles[3]
                dir_tiles[7] = dir_tiles[6]
                dir_tiles[0] = dir_tiles[5]
                dir_tiles[3] = dir_tiles[4]
                dir_tiles[6] = 0
                dir_tiles[5] = 0
                dir_tiles[4] = 0
                acc_tiles[8] = acc_tiles[7]
                acc_tiles[1] = acc_tiles[0]
                acc_tiles[2] = acc_tiles[3]
                acc_tiles[7] = acc_tiles[6]
                acc_tiles[0] = acc_tiles[5]
                acc_tiles[3] = acc_tiles[4]
                acc_tiles[6] = 0
                acc_tiles[5] = 0
                acc_tiles[4] = 0
        else
            tile_i = 5
            if dir_tiles[tile_i] == 0
                if first
                    ret['url'] = get_url(y_deg_next, x_deg_next, false)
                else
                    dir_tiles[tile_i] = dir_tile
                    acc_tiles[tile_i] = acc_tile
    if ret['url'] == 0
        if go
            x = x_next
            y = y_next
            x_deg = x_deg_next
            y_deg = y_deg_next
            mx = mx_next
            my = my_next
        ret['dir'] = dir_tiles[tile_i][y_next * tile_width + x_next]
        if acc_tiles[tile_i]? and acc_tiles[tile_i] != 0
            ret['acc'] = acc_tiles[tile_i][y_next * tile_width + x_next]
    return ret

p_wait = (ms) ->
    return new Promise((resolve, reject) ->
        setTimeout(resolve, ms)
        return
    )

p_getTile = (url, type) ->
    return new Promise((resolve, reject) ->
        getTile(url, type, resolve)
        return
    )

round = (number, precision) ->
    mult = Math.pow(10, precision)
    return Math.round(number * mult) / mult

get_url = (lat, lon, set_xy) ->
    lat = round(lat, 5)
    lon = round(lon, 5)
    ret = {}
    lat0 = 90
    lon0 = -180
    dir_code = {
        '40N_80W': 'njt5o2dpcx9lzig',
        '20N_30E': 'ls8f3pyhl7f3ysq',
        '70N_160E': 'rcdlrof5vnpq4u8',
        '40S_110E': 'pli2vv4tu7zg0vc',
        '10S_60W': 'vz169b4rb0dpokv',
        '10N_180E': '7cm7k4ns9efdyyj',
        '0N_0E': 'q3c4m9jlfpxqc63',
        '50N_70E': 'd9ihizwythu4mki',
        '50N_130W': '9l3gynlr804gw6k',
        '10S_60E': 'mxd445xbzoq68wz',
        '70N_60W': 'w4ksxwb2sxo92ia',
        '70N_90W': '643krk0ahqegh29',
        '60N_0E': 'ig9np311apxwywu',
        '40N_170E': 'a9f68i00sddb21h',
        '60N_90E': '7ppd0auquja7cha',
        '40N_60W': '6cqvbwcf4hjwbuq',
        '20S_100W': 'v0yeu59q4eopq2t',
        '0N_60W': '8h7bnwjhk36m4xq',
        '10N_140E': 'xo6kdts6wijvftn',
        '50N_100E': 'qr043ar5gaflp25',
        '40N_70W': 'fv02n108a3t471m',
        '60N_180E': 'wm7ai83hmlw0gbh',
        '50N_30E': '74bsr18q8aj5gzz',
        '10S_30E': 'bp2gai5uwkcolw2',
        '0N_50E': 'hqo12wfpq7q0ybe',
        '20N_150E': 'xpbqct99r7x1uxg',
        '10N_40E': 'kyko320y1xmzid6',
        '70N_50E': 'fjvhcu58630jg5t',
        '70N_100W': 'zm5uo7bo8so4ml4',
        '0N_80W': '4hrms9iaijj9quu',
        '50S_130E': 'x3lvela6fbjw32n',
        '30S_120E': 'pdmy538eze0j8ii',
        '20S_30E': 'us5v7ggmkb4j9jz',
        '10N_130E': 'rmm098zv13hjbcz',
        '20N_130E': '2ahcbqp11ymyyl5',
        '50N_110W': 'rqqtu2kfjbsg634',
        '30N_130W': 's2f49ctthghvnqa',
        '50N_40E': 'o4vx09kuzncbkm1',
        '40N_130E': 'cztyw8et0ofxzi8',
        '40N_180E': 'svm09gq9yz85yrm',
        '0N_170E': 'fw6prlx0d08x5o0',
        '10N_110E': '6jbc195o85tgx4l',
        '70N_70E': '469mlarc381lsom',
        '60N_80E': 'fxihjscygbq7m5v',
        '20S_20E': '1shz7rjreu3rmga',
        '20S_120E': 'vhturkmybky6or6',
        '10N_100W': 'a8e5grbrelki50k',
        '50N_0E': 'c95qdkj3t3ikt3u',
        '20N_20W': 'nuvxx950y7ko46f',
        '50N_100W': 'gjrtaneav8mc5he',
        '60N_130W': 'spwzdn8gm4406wo',
        '70N_180E': '8y8ldhxz48b50h0',
        '10S_100W': 'mdig6tpluqggw5r',
        '40N_30E': 'flmc5oftqvlcfvh',
        '20N_50W': '32j7an9zu6ppxob',
        '30N_120W': 'yz3r44lstmrbq4n',
        '20S_170E': 'raw3sdolobx5m6b',
        '30N_120E': 'webmh73x6nzykbq',
        '40S_50W': '9kcrobjb81urhf7',
        '30N_40E': 'aqswmk85xawse1x',
        '70N_150E': 'acy3j9jkybnnhfn',
        '20S_40E': 'dk9y0vb70stdbgo',
        '10S_90E': 'fzggjjsa4riaoxv',
        '20N_70E': '8o7uspbksjjjfte',
        '10N_60W': '1iu2g7qws543s77',
        '50N_180E': '86768dlqamgdhnp',
        '70N_40E': 'ebvr0x8xonc8tu9',
        '40N_90E': 'kgu11ddovji6qg0',
        '30N_60W': 'cjlju7rif77tm9p',
        '50S_140E': '0p7qhfjoezohmvg',
        '0N_150E': '59xy13gw2aftsoy',
        '20N_160E': 'r1tendiqpssbrgj',
        '30N_140E': 'gfdh6brfbu6ozr3',
        '60N_110W': '27glhbgxcvjdsj3',
        '40N_40E': '38x1dzu1hgmuo10',
        '70N_110E': 'ilfcu0jimcuu22y',
        '30S_100W': 'he5a0jhj7b3u37m',
        '50S_40W': 'ul76r0hqufkkito',
        '20N_100E': 'zv0ftnkg6978d1n',
        '0N_10E': 'e6zwm2ve6170rnc',
        '40S_70W': 'lt520yjkzvobjs0',
        '50N_130E': 'prr63cqsy2sq6l5',
        '50S_170E': 'j66g3gmsr97hz7w',
        '40N_100W': 'seu1iym7l3yawvr',
        '60N_10E': 'conbfw17m90cr65',
        '30N_70E': 'dgl15onm7366j9y',
        '40N_110W': 'x9d0c0nusvsnvkf',
        '0N_40W': '7d62jroploskrdz',
        '10N_30E': 'ufiiimxmi9q5rsq',
        '40N_10E': 'evdq82t5hnvlgup',
        '30N_150E': 'ju0vhdvs9q32mcf',
        '30N_80W': 'azwymrifj8020k5',
        '60N_30E': '3fo08jcqwvd2hri',
        '10N_20E': 'xue5zm4fbmzmo5l',
        '30N_100W': '7d4uan2bp2fyo5t',
        '20S_50W': 'lj5qpdmycd18i9s',
        '50N_80W': 'd01j1rqigwd6r4n',
        '30N_160E': '5huu7ehl9qvm434',
        '10S_50E': 'mp0r86di46cad30',
        '50N_90W': '62cjaxm4pwon3ta',
        '30S_70W': 'vcjchqdowlocrte',
        '70N_120E': 'z9vss9nffu130ya',
        '30N_130E': 'f1jumdi52vcg5hx',
        '20S_20W': 'ach4qdtxa6cvfoe',
        '60N_100W': 'iwcq9ogntx9h9zr',
        '0N_160E': 'cpmu98nntsai0fu',
        '50N_10W': 'jhfliz911qffjch',
        '60N_70E': 'rewb9fzmlpem67g',
        '20S_80W': '6yqay3jos6sthn9',
        '50S_50W': 'tt563tgfn2iccrm',
        '10S_10E': '10b693pj08lhph4',
        '0N_130E': 'n0yo92yfvocy2ys',
        '10N_50W': 'ni2bepgw20kfivr',
        '10N_120E': 'm4dqmeh8mkq8f09',
        '40N_160E': '3dfcmd7p8xvjyk5',
        '70N_10E': '3yfx21j7nggc6vg',
        '70N_30E': '4m9zcz4eueif5if',
        '30S_50E': 'ei77gp02xpl6234',
        '70N_80W': 'xsxbixdmjhuxbom',
        '40S_170E': '5tyi2av2p794x1k',
        '10N_0E': 'ut7jw1vksl7ospe',
        '50N_90E': '2tbtweuwsgououn',
        '70N_130E': 'pxqkn9t5b1lv16o',
        '50S_100W': 'jcch94px3a3lrkv',
        '30N_170E': 'x51q62qkeogycvj',
        '30S_110E': 'ref43ht78h1mxkl',
        '60N_100E': '91v4qmizu1t5chm',
        '70N_20W': 'cqysdk36jpky7sl',
        '10S_140E': 'sc1qd7xfskk1190',
        '50S_180E': '2r7oq34nuyrbrmz',
        '50N_20W': '0a3mfbgr4b3fwkf',
        '50S_60W': 'a3fakfcx18xebqw',
        '20N_100W': 'atj10syx395lock',
        '20N_40W': 'v78c8iig9u05c2c',
        '30S_40E': '9hjqr2yikdpp8pt',
        '10S_130E': 'uudwt6x8dp9w38o',
        '40N_150E': 'icd2nb7b7o6orbg',
        '50N_10E': 'r6uogmh1fpsg5gu',
        '20N_50E': 'znznm95m5u60fk3',
        '10S_160E': 'ibj3o24opajv5gl',
        '70N_10W': '57kfww0wfmvlr9c',
        '40N_10W': '93pww6nj0vdmkwh',
        '20N_110E': 'y2ltu7r6nulfn6z',
        '10N_20W': 'baivyy025t4gca6',
        '10N_80W': 'gksccwsgv0br8kv',
        '50S_80W': 'esgszubtsdhwc0d',
        '70N_0E': 'jmq6q20u1zzqe78',
        '10N_90W': 'ms46fc02ddfggaa',
        '40N_0E': 'brm28xvjp7txu6a',
        '40N_20W': 'j6aclal8hjj43sq',
        '20N_90E': '7kj50ke3t9dg2k1',
        '10N_70W': '1ehlf63ztq9ascf',
        '30S_10W': 'l76jxgrjc9chfq8',
        '30N_30E': 'c426bked8bs1p2x',
        '70N_140E': '0arx8x4o20tuc3j',
        '30N_110W': 'r50rg4dyyzlq2rp',
        '20N_80E': 'chyvj6484m3yyzw',
        '70N_170E': 'brlsfizhofanf9h',
        '50N_160E': '1bndf15xeaz75db',
        '60N_120E': 'qxun7audymzvs2j',
        '10S_120E': '4k9oiq72iojd7tw',
        '50N_120E': '1nvf48c3i5ntgfp',
        '50S_160E': 'kzzv6vaupevo667',
        '30N_20E': 'g59ucu9csoroh6d',
        '50S_110E': '5sc9507h87n9rk2',
        '20S_140E': '81plt39owmcx29t',
        '20S_40W': 'upmd0pogjc6vmwb',
        '10N_80E': 'qnumh0vszwhwg3e',
        '60N_120W': 'ekuqu87q69r1k24',
        '70N_110W': '6gaa13v5gnb7p3k',
        '50N_150E': 'm0voo0ef0t6ik5u',
        '10N_110W': 'pysk4tlowiynzkq',
        '10S_70W': 'b1buj0ma7xzkz9g',
        '40N_140W': 'q6hg1x2eapx4nzp',
        '0N_180E': 'xeq06zwex8tgz1g',
        '20S_50E': 'ry284o47frvh75s',
        '70N_80E': 'am8y1bepl6cimzq',
        '20S_10W': 'swy8xxdhqwkwzrf',
        '40N_80E': 'sq99xh0kj2e4iiu',
        '40S_130E': 'pniyneh9o29glhk',
        '50N_170E': 'osp3iio527u8a9m',
        '10N_40W': 'dhuv56y24w8k5nj',
        '30N_60E': 'vrdv94uy3p01gu9',
        '60N_50E': 'w6dokrajdg4vlx0',
        '60N_20W': 'pnlvqfblgfaaz4k',
        '60N_140W': 'igfgzntr4930h6s',
        '40N_50E': '30w4q6cpa4njbwb',
        '20S_160E': 'xmcripl7n2gygx8',
        '30N_70W': 'zq3bwir60cxbl2y',
        '10S_50W': 'ednjxma5fiup6l0',
        '30S_10E': '8wnoefc87uiiz8f',
        '20N_60E': 'wnf5qjng14lm3z6',
        '60N_110E': 'ecqbskcnw1qvx4d',
        '60N_70W': 'hwlnvkr1qrpnzc3',
        '40N_120W': 'z4797cg79jm46sd',
        '20S_70W': 'ewdv0bntx3xq090',
        '20S_150E': 'mhha19x5mf5seb2',
        '20N_80W': '41186p3wtvnp92a',
        '0N_50W': '9888rp2gt8ul4fl',
        '70N_100E': 'ukrwe7fx8ej6rkh',
        '10S_70E': 'zjslhzj7t3k05fr',
        '30S_140E': '71cke0qt9qj6qpo',
        '0N_10W': 'mqwhdvq5fpm5dvq',
        '60N_150E': 'hz1fv9czziyt4ft',
        '50S_70W': 'm2kycfffxxfuy3n',
        '30S_60W': 'mukv3pxvbwuxmv0',
        '20N_180E': 'vluofrfqlq1tq7d',
        '30S_80W': 'cywvswzxjdu0rke',
        '20S_60W': '9j6n6fn7z21nr1x',
        '20N_120W': 'nkvf20ojt3uxfek',
        '0N_100E': 'vsurwf60amex45l',
        '20N_70W': '17bv1gg3a9o27j1',
        '50N_50E': 'o1cndow58eg4iht',
        '10S_40E': 'p6n7ppnucthj3ri',
        '50S_90W': 'd76j559itl1d94f',
        '40N_140E': 'p78aivsuyysht3s',
        '0N_110E': 'd208ls5h0kaagjr',
        '10S_180E': 'ovzi3yf799mdb7l',
        '20N_0E': 'l70nfmxvozjd7k7',
        '40N_130W': '9v5iq543yn2ns9n',
        '0N_20E': 'g5riug5jsfevtcv',
        '0N_20W': '1thdgulzf3ziwrt',
        '40S_90W': 'tiyymuz1v8z4z31',
        '40S_150E': 'j3op3bvu8m1okp5',
        '20S_110E': 'xj5a0fv2r6auchr',
        '20N_20E': '1p7asnpmqw9rq4u',
        '10S_20W': 'vv5xszaadhckg6d',
        '0N_70W': 'c3as6denh34ke5g',
        '30S_90W': 'lus6tbpitf8j9po',
        '20N_170E': '1ugbxtppm7x13vl',
        '60N_170E': 'a98i7rcqx5fvlbk',
        '30N_140W': 'klbrzjdsqub1wku',
        '30S_40W': 'lqcr3kc5v800l8c',
        '0N_90W': '0r0zd2dpg8kt3ds',
        '50S_150E': '49ilumtcabfq22g',
        '30S_0E': 'ervrbl0m3tvnpu3',
        '0N_40E': 'z6u00g9m0rdpesh',
        '30N_90E': '3rrz6jwiueeg0be',
        '70N_60E': 'mipyttald7cgs6d',
        '40N_110E': 'vbff46frv6pgkmu',
        '10N_70E': 'bfyxhbb0mejotb6',
        '30N_110E': 'mduywyb0ut5whmp',
        '10N_90E': '5e2weozv466qvq9',
        '20N_10W': 'nj0uz42z5rog76o',
        '50S_120E': 'iu81a15u7gp3nq4',
        '20S_130E': 'fs9s3xadluqlv5g',
        '30N_80E': 'fwswppy42c91zy6',
        '40S_180E': 'v6vj008uec9ja7t',
        '60N_160E': '5zpvo2b7vktti7a',
        '40S_100W': '7zg5lxozkgomo5p',
        '0N_60E': 'vqyqo67uszxkezj',
        '30S_20W': 'fud1p0ywbpmt03t',
        '10S_170E': 'nw5y90t4ntqtahj',
        '30N_90W': '9u9w2ov3cuw8ue2',
        '20N_140E': 'wbhp6xp57lbqu5b',
        '60N_130E': 'tfkokya89ywzrjf',
        '70N_130W': 'sk24ldyi0gez2y4',
        '40S_140E': '6t0ndzci1yvvzos',
        '40N_20E': '46y8e2drvpc0558',
        '20S_0E': 'km8fieuehf0ievc',
        '60N_60W': 'a607whft4tau57h',
        '10N_170E': 'v3yvprk884a4r40',
        '30S_130E': '7y6wgnf7ndwyyll',
        '30N_180E': 'hndze8kj0psdo9r',
        '0N_70E': '0aet2epmdtvnj3i',
        '30S_30E': 'x2rahasj2aewd46',
        '50N_60E': 'a3dsjcsd0fuog8n',
        '20N_60W': 'o9ufvfwny6q42do',
        '10N_10W': '6k8ral35jl00z8g',
        '40N_120E': '7jq4kyvdn87x4i5',
        '70N_20E': 'aueplubete1o2xd',
        '30N_100E': 'lfz50uivpdqb166',
        '40N_90W': 'vju0gkkfoa773o0',
        '10S_80W': '0ruc1riqnl3rzza',
        '10N_60E': 'n5ee7k9mfto1104',
        '0N_120E': 'sswv3cdzvyst3e9',
        '70N_140W': '4quswlwtvxn456c',
        '10S_80E': 'jo5p4do02ubwhbm',
        '0N_90E': 'iq7i2v764t4ha22',
        '0N_140E': 'jg6r27k9l4u32d6',
        '60N_40E': '907q33vq6a5o0fk',
        '10N_150E': 'ka1m1y1dha1z75c',
        '60N_140E': '0gid8dmrylip35b',
        '30N_0E': 'r7fe9ugsky80kz8',
        '50N_20E': '3ey731tlb7duy0m',
        '30S_50W': '1dlgwyangl2jnoe',
        '50N_140E': '528kneauqf3d1ip',
        '30S_180E': '1phrgmq8kstmabk',
        '30N_10W': '2rgou9qbqg3k3m9',
        '10S_0E': 'iyp67d9ksbx90x2',
        '0N_80E': 'sikidycmwntrrhl',
        '30S_150E': '2v7kjt4wgbu6uc4',
        '20N_10E': 'ipewhaim6kmcla1',
        '0N_100W': 'sh8m2mmxm0iznka',
        '60N_20E': '7ax1ly9l8s1brzn',
        '60N_10W': 'i81h1aerrhvppqo',
        '10S_10W': 'rf5bmnkwv4395tl',
        '50N_80E': 'axibpl1v3u6643c',
        '10N_160E': '6t399mcnovfvhhg',
        '10N_100E': 'vzznnr63l8ku0bs',
        '20N_110W': 'aq4jnu47230b7hy',
        '50N_120W': '3mqc9wub3lvt9um',
        '30N_50E': 'vaf57pswj0aqfsy',
        '40N_100E': 'h2h4mpg5oi2e54l',
        '30S_170E': 'xkx6036h76ecjx6',
        '10S_20E': 'vc7sn3ig5jheb5k',
        '40S_80W': 'vqwe0k1u9k1qm73',
        '60N_90W': '48j6ie4tr6jec12',
        '60N_80W': 'krvh5e1nw4s9i5x',
        '70N_70W': 'evb65pwb599es77',
        '50N_110E': 'hckwm8kss4s09yz',
        '10S_150E': 'xk2vrdpvffsw70f',
        '10S_100E': '69qzfyqj37bdzqo',
        '0N_30E': '8yn50z10zvxuxd8',
        '70N_90E': 'u5om8ivcg5g663u',
        '20S_180E': 'vln4eo9vjz0xpie',
        '10S_90W': 'rdwm5zsqb80xz2o',
        '50N_60W': '4iu67oqfj6112z7',
        '10S_40W': '7hcb9keu1g2zij2',
        '40S_60W': 'qgef1cr6lx7dnmd',
        '20N_40E': '45pfkm2wq0xbzdt',
        '20N_120E': 're9vszajn3g2kun',
        '40S_40W': '1e40jbe1kpadu4a',
        '70N_120W': 'kat0kityhil0udo',
        '40N_60E': 'tfhm8s5v8at0np7',
        '10S_110E': '23u98dlaf4ijfyx',
        '10N_50E': '4k0vr9qphd7zxg8',
        '30N_10E': '70ksdpgfdyw0xx1',
        '10N_10E': 'naw02lg2pnkc3on',
        '40N_70E': 'ovmgwi1ihsskf8w',
        '20N_90W': 'c6df5dqbun2fks6',
        '30S_160E': '4bkneeoybdekmhj',
        '10N_120W': 'd85cl3w5esblmdv',
        '40S_160E': 'eiznsrt6teww45l',
        '50N_70W': '2kkzkjo7wghnh0y',
        '20S_10E': '0higj0z4ufomc7i',
        '40S_120E': 'maodj881wx8mr11',
        '60N_60E': 'q9nk7xu6exy9olg',
        '30S_20E': '8g3og3gnzf8wtcb',
        '30N_20W': 'st34jv53y9uibap',
        '20S_90W': '7ca1iymo44vtapg',
        '50N_140W': 'a8x97yts3pns2zd'
    }
    acc_code = {
        '40N_80W': '1ved2kan3vekbsl',
        '20N_30E': 'o9h8vj2ijk6m30q',
        '70N_160E': 'klthf1g5ret2m33',
        '40S_110E': 'ekwei5npdr5xad2',
        '10S_60W': 'z72r1g8gyberk9r',
        '10N_180E': '9adjaianil6k336',
        '0N_0E': 'u5q0yh2mnnrusoo',
        '50N_70E': 'xe7wbxrmdr1kdpx',
        '50N_130W': 'ln1lpe9d5ggr6r3',
        '10S_60E': 'x56jg8ybxsr0ho5',
        '70N_60W': 'f66xui5cm8yyesh',
        '70N_90W': 'yf7cdi0twry249d',
        '60N_0E': 'vkkd3ztom4o55iv',
        '40N_170E': 'r4rxv4le29zqg71',
        '60N_90E': 'u37cnk2rhbnapgo',
        '40N_60W': 'pdjk204mrpbebd5',
        '20S_100W': 'jmq6vqj4pckshhw',
        '0N_60W': '609y6fvzfav6r9c',
        '10N_140E': '58b7o4nu4the37s',
        '50N_100E': 'slnh3ovu9fl84ge',
        '40N_70W': '2wptr7ocyqlxfxt',
        '60N_180E': 'k6c7s848a230nw7',
        '50N_30E': '7wenzy53j3qehje',
        '10S_30E': 'wge2utgpkeho60r',
        '0N_50E': '9ky2mzqqr3jwfxt',
        '20N_150E': 'zah85leix3i58ro',
        '10N_40E': '9z9xra301g4qxct',
        '70N_50E': 'jgucp2gbxcirrtm',
        '70N_100W': '0rxn3xa7ohxy6n8',
        '0N_80W': '7e7lh1cvqx5vn04',
        '50S_130E': 'nrc2uxyvydnzity',
        '30S_120E': '2rrlzzpa7jqmett',
        '20S_30E': '8ww9vvb6k2ki27x',
        '10N_130E': 'hjo2rzqyhjvmzhn',
        '20N_130E': 't4h2bknods9z4dw',
        '50N_110W': 'nugk678qp1zz1rv',
        '30N_130W': 'khs4l62xgq2ca1d',
        '50N_40E': '7rbqq5c8z4o4j29',
        '40N_130E': 'z0bo6kr4g7wgukb',
        '40N_180E': 'roaa3xs0lakj1e1',
        '0N_170E': 'ptqo2vr0zn9s58a',
        '10N_110E': 'vhwrh4aach148ft',
        '70N_70E': 'gci003ln97lgod2',
        '60N_80E': '8viumh8teta6uy9',
        '20S_20E': '7t1p7z9u9sftvkw',
        '20S_120E': 'mpsfm0phc4yq1b9',
        '10N_100W': 'nos1jkms91aj3fs',
        '50N_0E': 'nojkk1j0zxfie57',
        '20N_20W': 'x0wxspucfcr0sva',
        '50N_100W': 'l0ykeqhll5b54ki',
        '60N_130W': 'vsd9oikgoyp60q6',
        '70N_180E': '4nd53y7yf2oicvo',
        '10S_100W': '3srrkh083g1i0wa',
        '40N_30E': 'yzzgnv3ebr58f2z',
        '20N_50W': 'g92fpng2kcfldxh',
        '30N_120W': 'yygwgrzxh7q22t0',
        '20S_170E': 'ysrxje659m24w48',
        '30N_120E': '5q68kw8h00y223j',
        '40S_50W': 'a481pn9fa4baum4',
        '30N_40E': 'gx3bww0tk1da056',
        '70N_150E': 'janhvi2onhs2zhp',
        '20S_40E': '0ltnnn3o77qqtnc',
        '10S_90E': 'l248w4dtw6y6ptf',
        '20N_70E': 'y2ljsg1sb44hbll',
        '10N_60W': 'y2tguxj9hzn5xkx',
        '50N_180E': 'o1q6s8rcmdt720i',
        '70N_40E': 'up6i2yyebb0h08e',
        '40N_90E': 'ycnsxa2t7g9g2v2',
        '30N_60W': 'bku0ozbdtnz9na1',
        '50S_140E': 'x49y3muxvwhdpjq',
        '0N_150E': 'u82agfojota1fae',
        '20N_160E': 'u0u0hadbocw835y',
        '30N_140E': '96ntdaakrwutqad',
        '60N_110W': 'f7czflhd23i65go',
        '40N_40E': 'fvsnrqs8iwb29wl',
        '70N_110E': 'zq3ljgaic2e9l95',
        '30S_100W': 'hfyfm57ql7de8bz',
        '50S_40W': '1acgix52dbb35dr',
        '20N_100E': 'e6dbte0icjl4to9',
        '0N_10E': 'd5j63eo01u2eqk3',
        '40S_70W': 'kv2k0cmvfqts6ln',
        '50N_130E': '498i9pd63z4o8qx',
        '50S_170E': 'kbiv8xndt8klayn',
        '40N_100W': 'q9ntdv83y2af92i',
        '60N_10E': 'q3hry1ynwmygsw2',
        '30N_70E': 'dt777z4rjbfd7zj',
        '40N_110W': '2kixpoy887c8m1u',
        '0N_40W': '20vdr5ckl8379tv',
        '10N_30E': '32bti0lht8zcc0q',
        '40N_10E': 'wlps5rzyu8zpneh',
        '30N_150E': '4r9ild45k6eotwa',
        '30N_80W': 'lilh4vn8ttsm5uj',
        '60N_30E': 'yo39wrscza39760',
        '10N_20E': 'p1z618d5kg2fzx6',
        '30N_100W': 'kz2oqfwiq4v6oqy',
        '20S_50W': 's6ydvacxz6wu002',
        '50N_80W': '5pfnm5mgeb1b4ra',
        '30N_160E': 'qip5z92n0qm015i',
        '10S_50E': '56q4xt1lbxqj5sr',
        '50N_90W': 'l2n6cabbgbjbf5o',
        '30S_70W': 'cl23iobynea5vxe',
        '70N_120E': 'i004g9vtb8cvbkh',
        '30N_130E': 'b44sr2kq4nr7zmb',
        '20S_20W': '753lvlvmspbkcdz',
        '60N_100W': '8bpfdegm7qsah8j',
        '0N_160E': 't2vfr58loly7nq7',
        '50N_10W': 'ht7lv8x1pvrwgu3',
        '60N_70E': 'nl2sny6ngiqn29z',
        '20S_80W': 'htvyq0934mce6yf',
        '50S_50W': '4uw9lncxnc6aooh',
        '10S_10E': '0e8seiw76bhqirl',
        '0N_130E': '6w1ol7wjtcbnmi9',
        '10N_50W': 'zpin530cddrwmd2',
        '10N_120E': '4li1ej0ps5b4klx',
        '40N_160E': 'zo4un5mx4hgaadd',
        '70N_10E': 'km38smdivknnscz',
        '70N_30E': 'e6ar3eoavztnzco',
        '30S_50E': '7pjdrhru3ki5lbg',
        '70N_80W': 'dxb9l4wim1q6uyb',
        '40S_170E': '9cnaqql903acuaj',
        '10N_0E': 'm306xdm44lcjlgt',
        '50N_90E': '66e8nawohn35jn8',
        '70N_130E': 'rkg0926pjdgk44q',
        '50S_100W': 'aeltjkwgozaxn3n',
        '30N_170E': '0aka4yndzsubps2',
        '30S_110E': 'pmpktexl2a7woq4',
        '60N_100E': 'yt2pdig650y7biv',
        '70N_20W': 's1hlmk5u7le7vva',
        '10S_140E': 'dss4u7br879bz8l',
        '50S_180E': '0yrq5i176uopxfd',
        '50N_20W': 'ptir73a65vtiuw5',
        '50S_60W': 'nlfu1pr1a5j559b',
        '20N_100W': 'mrv0nm276cbk194',
        '20N_40W': '0gokx9vaxkrhjuw',
        '30S_40E': '49abx691nc0wqnw',
        '10S_130E': 'a1uylfk4o4qw3y0',
        '40N_150E': 's8e702b97g1324n',
        '50N_10E': '278ptugzt8q91kg',
        '20N_50E': '0lirmd85t2yq8yc',
        '10S_160E': 'mt7f3ue90hroheh',
        '70N_10W': 'o1h3xr4ffqjm2os',
        '40N_10W': '5aqkfjllngb9il6',
        '20N_110E': 'l6irz27x6mruztc',
        '10N_20W': '7cmnquu9e0twzs7',
        '10N_80W': '3hszs1dhw5bo90y',
        '50S_80W': '0lmmdg1iz6b8ioc',
        '70N_0E': 'q06w5i71fi0zimu',
        '10N_90W': '1kk9cfby83p7ixe',
        '40N_0E': '18yuy7hwyti1b5p',
        '40N_20W': 'lxydcs6kltq98la',
        '20N_90E': 'pjqjrrh085hhfuh',
        '10N_70W': 'fynnojelnn59wte',
        '30S_10W': 'd1f6hvr10bjy4gf',
        '30N_30E': 'h5eb6mzt5do9242',
        '70N_140E': 'jdrg6tu0vumzzxi',
        '30N_110W': 'q25wx329xuxkf2x',
        '20N_80E': 'c5gt41a3q87ru6a',
        '70N_170E': 'vijxss0uafkr965',
        '50N_160E': '3wnqfmeurjch8x0',
        '60N_120E': 'bidvt7aq4mumag8',
        '10S_120E': 'b22tpcoxd6ewisj',
        '50N_120E': 'sejdogzt14n9r7k',
        '50S_160E': 'k6p592etkm2ln0q',
        '30N_20E': 'a8ma6hpbb1llory',
        '50S_110E': '92ps5mt0xkeioaj',
        '20S_140E': 'gvtjj7bn5oh4yuj',
        '20S_40W': 'gramumt58cnone1',
        '10N_80E': 'jztppvi37ykksgp',
        '60N_120W': 'a47x9x5l93eguyb',
        '70N_110W': 'ipmmfyewateko23',
        '50N_150E': 'guzf92rft42cml1',
        '10N_110W': 'y5cxk53a2stnnhn',
        '10S_70W': '6ca079u2rzh5x2z',
        '40N_140W': 'ntutatlh7b5daca',
        '0N_180E': 'c0you9jbuj95p7g',
        '20S_50E': 'ypptooy7uukqz8f',
        '70N_80E': 'i95qsmzr33do0uy',
        '20S_10W': '7rnrzty3v5nszdg',
        '40N_80E': '5bjysl4e9j0kx43',
        '40S_130E': 'mmfkzwmo5q6ocg4',
        '50N_170E': '0wd7jko131d6fr7',
        '10N_40W': '47h0pkunr4pa2rb',
        '30N_60E': '3atu4qvckn3jz14',
        '60N_50E': 'gec098zgkta4j9m',
        '60N_20W': 'gca31zqn0hchs7e',
        '60N_140W': 'q79xh4a98screhw',
        '40N_50E': '0jlph6i8ueujam3',
        '20S_160E': 'j4evc8m7fgkwbpl',
        '30N_70W': 'eqmuf0p8iv75cex',
        '10S_50W': '6aykphbtpo760n2',
        '30S_10E': 'vak4x1t7om2wdju',
        '20N_60E': 'dgouprne9l0uudt',
        '60N_110E': 'jyvoiq8my3dxmfa',
        '60N_70W': '4ldkrq5qed3box3',
        '40N_120W': 'p1i1y1s4uz95evw',
        '20S_70W': 'vrmih7pxxrdtqq4',
        '20S_150E': '07rwp4utlcl3ouv',
        '20N_80W': 'c2s5fr0mbr43bcm',
        '0N_50W': 'jp3tovpgkja25u3',
        '70N_100E': '6kqxsunmrnrxarz',
        '10S_70E': 'onwwqgbwt0c0b0z',
        '30S_140E': 'bakdtyf1mpwiv0k',
        '0N_10W': 'aiq2a6nerz07yqf',
        '60N_150E': 'kihqdsxf5x3dznq',
        '50S_70W': 'c3glzc43044exsa',
        '30S_60W': 'b4hpbycf0ol6yab',
        '20N_180E': '6lr6pt5jl0bzfkc',
        '30S_80W': 'kn02lodxtu7lnzp',
        '20S_60W': '28ugfazgzfe87gp',
        '20N_120W': 'rb43lho32j5czwx',
        '0N_100E': 'bjzi4mml4tqu2f5',
        '20N_70W': 'ul4lpbww7vdwjje',
        '50N_50E': 'cfdf285rwzf2sqp',
        '10S_40E': 'h0l6o6h6ofw1q80',
        '50S_90W': 'p5iofs8666fxbxa',
        '40N_140E': 'fpzrk5izl52rv8c',
        '0N_110E': 'bysszkoxmtzuemf',
        '10S_180E': '3mzchkafk1gvr6e',
        '20N_0E': '34bcbhy3zsoiulb',
        '40N_130W': 'zbaszmug8192l3v',
        '0N_20E': 'tvtmqcidqxjdws1',
        '0N_20W': '8x2o46awzj96d3e',
        '40S_90W': 'r105ztwzibpshln',
        '40S_150E': '9sxhwki1nx8ybke',
        '20S_110E': '5jbkw9wy557ro8r',
        '20N_20E': 'ofdgzf4be318x8a',
        '10S_20W': 'ng23rt7c4tm0gne',
        '0N_70W': '697duu0xpn8bixo',
        '30S_90W': '6bov73ainrj3znm',
        '20N_170E': 'vfr2hbatxgibpno',
        '60N_170E': 'brrfp9g6w4155qd',
        '30N_140W': 'm75vqj9cjrdnqfx',
        '30S_40W': 't6johnvl1pj0300',
        '0N_90W': '0qugd8md0cqj63j',
        '50S_150E': '8rxzq57q7e6u7v1',
        '30S_0E': 'eg9stb15siypv0f',
        '0N_40E': 'xt3njvyww42bk81',
        '30N_90E': 'jj3kk4yp0doo913',
        '70N_60E': '0r5kaxhuh5rhsmg',
        '40N_110E': '6ylcosoqyt2yvmi',
        '10N_70E': 'wx6kdphbqffbm3a',
        '30N_110E': 'yjv3ivfyfm0b2hg',
        '10N_90E': 'jt0x4fh0q7lgdr4',
        '20N_10W': 'zdlpwl03s65v4f7',
        '50S_120E': '4qo04d31u7fi7um',
        '20S_130E': 'sq9y0ibchowcagr',
        '30N_80E': '1rl1wi810didfsg',
        '40S_180E': '1d9ns4cl1zwuovz',
        '60N_160E': 'af8wf7vu6jkpbh8',
        '40S_100W': 'xb3wftqfd9c5hrh',
        '0N_60E': 'bhpel9girxcsqr1',
        '30S_20W': 'p6ad5n7oouhl3rd',
        '10S_170E': 'i866eq5cw5wpg52',
        '30N_90W': '9bnu2f5uovpt6nh',
        '20N_140E': '251va047pcfj405',
        '60N_130E': '0ig97jnmzr8fep6',
        '70N_130W': '76zn1m0v4fu9g8l',
        '40S_140E': 'buejm7ea2fnsk6f',
        '40N_20E': 'jon2o5l6t52xzoc',
        '20S_0E': 'g9dehl04jm6vu6g',
        '60N_60W': 'v5qmiw3ldikoaz6',
        '10N_170E': 'xvmle7433kiomg7',
        '30S_130E': 'kp9c6waef0l76d1',
        '30N_180E': '0l4b2uz3zw7yn73',
        '0N_70E': 'jh7uywpo6q53zb5',
        '30S_30E': 'alqkbwb00u1lj63',
        '50N_60E': 'gibjbk7kupxhe58',
        '20N_60W': 'e6wurhqsbjf6gtr',
        '10N_10W': '95ofejfrjm9k58g',
        '40N_120E': 'uo5w705tutbh70q',
        '70N_20E': 'o96ya3xzibmqonk',
        '30N_100E': 'efdmfg38d9ekzxt',
        '40N_90W': 'et2fov3vyhq54fx',
        '10S_80W': 'qez988ku98a7i9h',
        '10N_60E': 'bnw1ial6k07gu3i',
        '0N_120E': 'ull57q38z44mh2c',
        '70N_140W': 'dcclz4i48ut8c0u',
        '10S_80E': '2xkuxc1tfa2r13d',
        '0N_90E': '92cxzfoyg9w72x3',
        '0N_140E': 'ae2sc1lrdl66lce',
        '60N_40E': 'nlvlv1rvefib6uo',
        '10N_150E': '3yez5ap8dw7lrdn',
        '60N_140E': 'xp3if3usno35w0p',
        '30N_0E': '1gl1wpztfp0qn1v',
        '50N_20E': 'jccc2k1t1jotx86',
        '30S_50W': 'y6mvxcemb8yxd45',
        '50N_140E': 'x0xy4m8w5rk9rxh',
        '30S_180E': 'wd34pzjk00f3p05',
        '30N_10W': 'v7zpypbixobmfnw',
        '10S_0E': '2smm6b8fdd6fqgz',
        '0N_80E': 'lfdzunxzy0s65ia',
        '30S_150E': 'q8px3skpsj0lwxm',
        '20N_10E': 'kyxjthcglt3ivas',
        '0N_100W': 'b5ugfvrg2ln2a2w',
        '60N_20E': 'ihhosm9fb1o6kq7',
        '60N_10W': 'bor1buuxdeashf2',
        '10S_10W': 'typwu7umuwdamy5',
        '50N_80E': 'ionzyhws088mbbb',
        '10N_160E': 'dj53kiemnpoovz0',
        '10N_100E': 'k86cfaq6h7fzczi',
        '20N_110W': 'acomjfnfhnv61oc',
        '50N_120W': 'hhbtakwte1padxa',
        '30N_50E': 'r77qwgr3bnc2dfl',
        '40N_100E': 'uvxqn9zmty0xyot',
        '30S_170E': 'af72iixuts7nwis',
        '10S_20E': '40iqlgjy0ofh4ad',
        '40S_80W': 'sop9l4se8dpmr0f',
        '60N_90W': 'qjs3b80ury88dnu',
        '60N_80W': '0029hmwoy2gle4m',
        '70N_70W': '7a6qs5tr8xp2uzw',
        '50N_110E': '7y8fcf2mfllrjgf',
        '10S_150E': 'wn4ekf7pg26okzh',
        '10S_100E': 'nom9miej8tvtnl3',
        '0N_30E': 'ov4bp27pvc801jz',
        '70N_90E': '3opeojskv2sjdmb',
        '20S_180E': 'gdib7omfksf13b8',
        '10S_90W': '9rvxr91rvh5gt5h',
        '50N_60W': 'w81v37rfq7gtliw',
        '10S_40W': 'b5e24keufggg727',
        '40S_60W': 'tozaj4c9n7f6ugp',
        '20N_40E': 'x7jvjla2u0jxvfg',
        '20N_120E': 'bag7ujuevjff7g0',
        '40S_40W': 'cxrldzr6c7gka4y',
        '70N_120W': '96078tel4uivool',
        '40N_60E': 'plgdilv716dyymy',
        '10S_110E': 'j89kbgedw1zwgu6',
        '10N_50E': 'ts06mf77sb9b8d6',
        '30N_10E': 'fhpd9s14thg82i5',
        '10N_10E': 'kp7czekbylf5qxd',
        '40N_70E': '1k2ybberpzn4785',
        '20N_90W': '88ton0j4luyfbx4',
        '30S_160E': 'eelidgbe0u3gjto',
        '10N_120W': '7iptjnboj7uh9ji',
        '40S_160E': '9ouncma6bo0sot3',
        '50N_70W': 'a2tb8j38d59j2yg',
        '20S_10E': 'rye3rs62fd3mssf',
        '40S_120E': 'no71dy1zg19e1j7',
        '60N_60E': 'aewa418pr2an1n3',
        '30S_20E': 'k1991ygz4vs4912',
        '30N_20W': '9cs53bxuk2si73a',
        '20S_90W': 'wbtf3za0y23vlan',
        '50N_140W': 'k3t0lsv4ccdfw67'
    }
    lon0 += 10 while lon >= lon0 + 10
    lat0 -= 10 while lat <= lat0 - 10
    if lat0 < 0
        lat_str = (-lat0).toString() + 'S'
    else
        lat_str = lat0.toString() + 'N'
    if lon0 < 0
        lon_str = (-lon0).toString() + 'W'
    else
        lon_str = lon0.toString() + 'E'
    tile_name = lat_str + '_' + lon_str
    dir_url = 'https://dl.dropboxusercontent.com/s/' + dir_code[tile_name] + '/tile_' + tile_name + '.bin?dl=1'
    acc_url = 'https://dl.dropboxusercontent.com/s/' + acc_code[tile_name] + '/tile_' + tile_name + '.bin?dl=1'
    if set_xy
        x = Math.floor((lon - lon0) / pix_deg)
        y = Math.floor((lat0 - lat) / pix_deg)
        x_deg = lon0 + x * pix_deg
        y_deg = lat0 - y * pix_deg
    return {'dir': dir_url, 'acc': acc_url}

L.mapbox.accessToken = 'pk.eyJ1IjoiZGF2aWRicm9jaGFydCIsImEiOiJ6eU40bEVvIn0.xnMppw5d4NoZK_11lA-lGw'
map = L.mapbox.map('map', 'examples.map-2k9d7u0c', {
    contextmenu: true,
    contextmenuWidth: 140,
    contextmenuItems: [{
        text: 'Show watershed',
        callback: (e) ->
            state = 'watershed'
            runGen(do_delineate, [e.latlng.lat, e.latlng.lng])
    }, {
        text: 'Show stream',
        callback: (e) ->
            state = 'stream'
            runGen(do_stream, [e.latlng.lat, e.latlng.lng])
    }, '-', {
        text: 'Show watersheds along stream',
        callback: (e) ->
            state = 'wsOnStr'
            runGen(do_stream, [e.latlng.lat, e.latlng.lng])
    }, {
        text: 'Show sub-watersheds',
        callback: (e) ->
            state = 'subWs'
            runGen(do_delineate, [e.latlng.lat, e.latlng.lng])
    }
    ]}).setView([-10, -60], 5)

map.on('click', (e) ->
    alert('LatLon = ' + round(e.latlng.lat, 3) + ', ' + round(e.latlng.lng, 3))
    return
)

layers = document.getElementById('menu-ui')
addLayer(L.mapbox.tileLayer('davidbrochart.1096eff6'), 'Flow accumulation', 1)
