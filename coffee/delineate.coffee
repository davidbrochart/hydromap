runGenerator = (g) ->
    it = g()
    # asynchronously iterate over generator
    iterate = (val) ->
        ret = it.next(val)
        if (!ret.done)
            # poor man's "is it a promise?" test
            if "then" in ret.value
                # wait on the promise
                ret.value.then(iterate)
            # immediate value: just send right back in
            else
                # avoid synchronous recursion
                f = () ->
                    iterate(ret.value)
                setTimeout(f, 0)
    iterate()

getTile = (url) ->
    console.log 'Downloading ' + url
    f = (resolve, reject) ->
        req = new XMLHttpRequest()
        req.open 'GET', url, true
        oReq.responseType = 'arraybuffer'
        oReq.onload = ->
            console.log 'Done!'
            arrayBuffer = oReq.response
            if arrayBuffer
                resolve(new Uint8Array(arrayBuffer))
        oReq.send(null)
    return new Promise(f)

processTile = ->
    while addPixel() then
    return

go_get_dir = (x, y, x_deg, y_deg, dir, go) ->
    tile_i = 0
    if dir == 1
        x += 1
        x_deg += pix_deg
    else if dir == 2
        x += 1
        y += 1
        x_deg += pix_deg
        y_deg -= pix_deg
    else if dir == 4
        y += 1
        y_deg -= pix_deg
    else if dir == 8
        x -= 1
        y += 1
        x_deg -= pix_deg
        y_deg -= pix_deg
    else if dir == 16
        x -= 1
        x_deg -= pix_deg
    else if dir == 32
        x -= 1
        y -= 1
        x_deg -= pix_deg
        y_deg += pix_deg
    else if dir == 64
        y -= 1
        y_deg += pix_deg
    else if dir == 128
        x += 1
        y -= 1
        x_deg += pix_deg
        y_deg += pix_deg
    if x == -1 and y == -1
        x = tile_width - 1
        y = tile_width - 1
        tile_i = 6
        if go
            tiles[1] = tiles[7]
            tiles[2] = tiles[0]
            tiles[3] = tiles[5]
            tiles[0] = tiles[6]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[4] = 0
            tiles[5] = 0
            tiles[6] = 0
            tiles[7] = 0
            tiles[8] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if x == tile_width and y == -1
        x = 0
        y = tile_width - 1
        tile_i = 8
        if go
            tiles[3] = tiles[1]
            tiles[4] = tiles[0]
            tiles[5] = tiles[7]
            tiles[0] = tiles[8]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[2] = 0
            tiles[1] = 0
            tiles[8] = 0
            tiles[7] = 0
            tiles[6] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if x == tile_width and y == tile_width
        x = 0
        y = 0
        tile_i = 2
        if go
            tiles[5] = tiles[3]
            tiles[6] = tiles[0]
            tiles[7] = tiles[1]
            tiles[0] = tiles[2]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[4] = 0
            tiles[3] = 0
            tiles[2] = 0
            tiles[1] = 0
            tiles[8] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if x == -1 and y == tile_width
        x = tile_width - 1
        y = 0
        tile_i = 4
        if go
            tiles[7] = tiles[5]
            tiles[8] = tiles[0]
            tiles[1] = tiles[3]
            tiles[0] = tiles[4]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[6] = 0
            tiles[5] = 0
            tiles[4] = 0
            tiles[3] = 0
            tiles[2] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if y == -1
        y = tile_width - 1
        tile_i = 7
        if go
            tiles[4] = tiles[5]
            tiles[3] = tiles[0]
            tiles[2] = tiles[1]
            tiles[5] = tiles[6]
            tiles[0] = tiles[7]
            tiles[1] = tiles[8]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[6] = 0
            tiles[7] = 0
            tiles[8] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if x == tile_width
        x = 0
        tile_i = 1
        if go
            tiles[6] = tiles[7]
            tiles[5] = tiles[0]
            tiles[4] = tiles[3]
            tiles[7] = tiles[8]
            tiles[0] = tiles[1]
            tiles[3] = tiles[2]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[8] = 0
            tiles[1] = 0
            tiles[2] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if y == tile_width
        y = 0
        tile_i = 3
        if go
            tiles[6] = tiles[5]
            tiles[7] = tiles[0]
            tiles[8] = tiles[1]
            tiles[5] = tiles[4]
            tiles[0] = tiles[3]
            tiles[1] = tiles[2]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[4] = 0
            tiles[3] = 0
            tiles[2] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    else if x == -1
        x = tile_width - 1
        tile_i = 5
        if go
            tiles[8] = tiles[7]
            tiles[1] = tiles[0]
            tiles[2] = tiles[3]
            tiles[7] = tiles[6]
            tiles[0] = tiles[5]
            tiles[3] = tiles[4]
            if tiles[0] == 0
                tiles[0] = yield getTile(get_url(y_deg, x_deg)['url'])
            tiles[6] = 0
            tiles[5] = 0
            tiles[4] = 0
        else
            if tiles[tile_i] == 0
                tiles[tile_i] = yield getTile(get_url(y_deg, x_deg)['url'])
    return
