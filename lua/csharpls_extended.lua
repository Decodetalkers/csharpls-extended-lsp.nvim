local utils = require("csharpls_extended.utils")

local M = {}

-- M.defolderize = function(str)
--     -- private static string Folderize(string path) => string.Join("/", path.Split('.'));
--     return string.gsub(str, "[/\\]", ".")
-- end

M.csharp_host = "csharp:/metadata"

M.client_name = "csharp_ls"

-- M.matcher = "metadata[/\\]projects[/\\](.*)[/\\]assemblies[/\\](.*)[/\\]symbols[/\\](.*).cs"

---@param url string
---@param start string
---@return boolean
function M.starts(url, start)
    return string.sub(url, 1, string.len(start)) == start
end

---@param uri string | nil
---@return boolean
M.is_lsp_url = function(uri)
    if uri == nil then
        return true
    end
    return M.starts(uri, M.csharp_host)
end

-- get client
--- @return vim.lsp.Client | nil
M.get_csharpls_client = function()
    local clients = vim.lsp.get_clients({ buffer = 0 })
    for _, client in pairs(clients) do
        if client.name == M.client_name then
            return client
        end
    end

    return nil
end

--- @class buf_from_metadata.result
--- @inlinedoc
--- @field source string
--- @field assemblyName string
---
--- @param result buf_from_metadata.result
--- @param client_id integer
--- @param uri string
--- @param buf integer | nil
---
--- @return integer
M.buf_from_metadata = function(result, client_id, uri, buf)
    local normalized = string.gsub(result.source, "\r\n", "\n")
    local source_lines = utils.split(normalized, "\n")

    -- this will be /$metadata$/...
    local bufnr = buf or utils.get_or_create_buf(uri)
    -- TODO: check if bufnr == 0 -> error
    vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", false, { buf = bufnr })
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
    vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
    vim.api.nvim_set_option_value("readonly", true, { buf = bufnr })
    vim.api.nvim_set_option_value("filetype", "cs", { buf = bufnr })
    vim.api.nvim_set_option_value("modified", false, { buf = bufnr })

    -- attach lsp client ??
    vim.lsp.buf_attach_client(bufnr, client_id)

    return bufnr
end

--- @class handle_locations.ret
--- @inlinedoc
--- @field filename string
--- @field lnum integer
--- @field col integer
--- @field range lsp.Range
--- @field uri lsp.URI
--- @field text string
--- @field user_data lsp.Location|lsp.LocationLink
---
-- Gets metadata for all locations with $metadata$
-- Returns: boolean whether any requests were made
---@param locations lsp.Location[]|lsp.LocationLink[]
---@param offset_encoding string offset_encoding for locations utf-8|utf-16|utf-32
---@param buf integer|nil
---@return handle_locations.ret[]
M.get_metadata = function(locations, offset_encoding, buf)
    local client = M.get_csharpls_client()
    if not client then
        -- TODO: Error?
        return {}
    end

    local fetched = {}
    for _, loc in pairs(locations) do
        -- url, get the message from csharp_ls
        local uri = utils.urldecode(loc.uri)

        --if has get messages
        local is_meta = M.is_lsp_url(uri)
        if not is_meta then
            table.insert(fetched, {
                filename = vim.uri_to_fname(loc.uri),
                lnum = loc.range.start.line + 1,
                col = loc.range.start.character + 1,
                range = loc.range,
                uri = loc.uri,
            })
            goto continue
        end
        local params = {
            timeout = 5000,
            textDocument = {
                uri = uri,
            },
        }
        -- request_sync?
        -- if async, need to trigger when all are finished
        local result, err = client.request_sync("csharp/metadata", params, 10000, 0)
        if not err and result ~= nil then
            local bufnr = M.buf_from_metadata(result.result, client.id, uri, buf)
            -- change location name to the one returned from metadata
            -- alternative is to open buffer under location uri
            -- not sure which one is better
            loc.uri = vim.uri_from_bufnr(bufnr)
            table.insert(fetched, {
                filename = vim.uri_to_fname(loc.uri),
                lnum = loc.range.start.line + 1,
                col = loc.range.start.character + 1,
                bufnr = bufnr,
                range = loc.range,
                uri = loc.uri,
            })
        end
        ::continue::
    end
    fetched = vim.tbl_deep_extend("force", fetched, vim.lsp.util.locations_to_items(fetched, offset_encoding))

    return fetched
end

--- @param result lsp.Location | lsp.Location[]
--- @return lsp.Location[]
M.textdocument_definition_to_locations = function(result)
    if not vim.islist(result) then
        return { result }
    end

    return result
end

--- The location should first handled by locations_to_items
---@param locations lsp.Location[]|lsp.LocationLink[]
---@param offset_encoding string offset_encoding for locations utf-8|utf-16|utf-32
---
--- @return boolean
M.handle_locations = function(locations, offset_encoding)
    local fetched = M.get_metadata(locations, offset_encoding)

    if not vim.tbl_isempty(fetched) then
        if #locations > 1 then
            utils.set_qflist_locations(fetched)
            vim.api.nvim_command("copen")
            return true
        else
            if vim.fn.has('nvim-0.11') == 1 then
                vim.lsp.util.show_document(locations[0], offset_encoding, { focus = true })
            else
                -- NOTE: for nvim < 0.11
                vim.lsp.util.jump_to_location(locations[1], offset_encoding)
            end
            return true
        end
    else
        return false
    end
end

M.handler = function(err, result, ctx, config)
    -- fixes error for "jump_to_location must be called with valid offset
    -- encoding"
    -- https://github.com/neovim/neovim/issues/14090#issuecomment-1012005684
    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    local locations = M.textdocument_definition_to_locations(result)
    local handled = M.handle_locations(locations, offset_encoding)
    if not handled then
        return vim.lsp.handlers["textDocument/definition"](err, result, ctx, config)
    end
end

M.lsp_definitions = function()
    local client = M.get_csharpls_client()
    if client then
        local params
        if vim.fn.has('nvim-0.11') == 1 then
            params = vim.lsp.util.make_position_params(0, 'utf-8')
        else
            params = vim.lsp.util.make_position_params()
        end
        local handler = function(err, result, ctx, config)
            ctx.params = params
            M.handler(err, result, ctx, config)
        end
        client.request("textDocument/definition", params, handler)
    end
end

M.gen_virtual_file = function(location, buf)
    local client = M.get_csharpls_client()
    if not client then
        -- TODO: Error?
        return {}
    end

    -- url, get the message from csharp_ls
    local uri = utils.urldecode(location)

    local params = {
        timeout = 5000,
        textDocument = {
            uri = uri,
        },
    }
    -- request_sync?
    -- if async, need to trigger when all are finished
    local result, err = client.request_sync("csharp/metadata", params, 10000, 0)
    --print(result.result.source)
    if not err and result ~= nil then
        M.buf_from_metadata(result.result, client.id, uri, buf)
    end
end

M.virtual_text_document = function(params)
    local bufnr       = params.buf
    local actual_path = params.file

    M.gen_virtual_file(actual_path, bufnr)
end

M.buf_read_cmd_bind = function()
    vim.api.nvim_create_autocmd({ "BufReadCmd" }, {
        pattern = { "csharp:/*" },
        callback = M.virtual_text_document
    })
end

return M
