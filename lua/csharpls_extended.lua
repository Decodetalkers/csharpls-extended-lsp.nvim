local utils = require("csharpls_extended.utils")
--local lsp_util = require 'vim.lsp.util'

local finders = require("telescope.finders")
local conf = require("telescope.config").values
local pickers = require "telescope.pickers"
local lspconfig = require "telescope.config"
local make_entry = require "telescope.make_entry"
local M = {}

M.defolderize = function(str)
    -- private static string Folderize(string path) => string.Join("/", path.Split('.'));
    return string.gsub(str, "[/\\]", ".")
end

M.matcher = "metadata[/\\]projects[/\\](.*)[/\\]assemblies[/\\](.*)[/\\]symbols[/\\](.*).cs"
--M.matcher_meta_uri = "(metadata%$[/\\].*)"

-- it return a nil?
M.parse_meta_uri = function(uri)
    --print(uri)
    --local found, _, project, assembly, symbol = string.find(uri, M.matcher)
    local found, _, project, assembly, symbol = string.find(uri, M.matcher)
    --print(found)
    if found ~= nil then
        return found, M.defolderize(project), M.defolderize(assembly), M.defolderize(symbol)
    end
    return nil
end

-- get client
M.get_csharpls_client = function()
    local clients = vim.lsp.buf_get_clients(0)
    for _, client in pairs(clients) do
        if client.name == "csharp_ls" then
            return client
        end
    end

    return nil
end

M.buf_from_metadata = function(result, client_id)
    local normalized = string.gsub(result.source, "\r\n", "\n")
    local source_lines = utils.split(normalized, "\n")

    -- normalize backwards slash to forwards slash
    local normalized_source_name = string.gsub(result.assemblyName, "\\", "/")
    local file_name = "/" .. normalized_source_name

    -- this will be /$metadata$/...
    local bufnr = utils.get_or_create_buf(file_name)
    -- TODO: check if bufnr == 0 -> error
    vim.api.nvim_buf_set_option(bufnr, "modifiable", true)
    vim.api.nvim_buf_set_option(bufnr, "readonly", false)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, source_lines)
    vim.api.nvim_buf_set_option(bufnr, "modifiable", false)
    vim.api.nvim_buf_set_option(bufnr, "readonly", true)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "cs")
    vim.api.nvim_buf_set_option(bufnr, "modified", false)

    -- attach lsp client ??
    vim.lsp.buf_attach_client(bufnr, client_id)

    -- vim.api.nvim_win_set_buf(0, bufnr)

    -- set_cursor is (1, 0) indexed, where LSP range is 0 indexed, so add 1 to line number
    -- vim.api.nvim_win_set_cursor(0, { range.start.line+1, range.start.character })
    --
    return bufnr, file_name
end

-- Gets metadata for all locations with $metadata$
-- Returns: boolean whether any requests were made
M.get_metadata = function(locations)
    local client = M.get_csharpls_client()
    if not client then
        -- TODO: Error?
        return false
    end

    local fetched = {}
    for _, loc in pairs(locations) do
        -- url, get the message from csharp_ls
        local uri = utils.urldecode(loc.uri)
        --print(uri)
        --if has get messages
        local is_meta, _, _, _ = M.parse_meta_uri(uri)
        --print(is_meta,project,assembly,symbol)
        if is_meta then
            --print(uri)
            local params = {
                timeout = 5000,
                textDocument = {
                    uri = uri,
                },
            }
            --print("ssss")
            -- request_sync?
            -- if async, need to trigger when all are finished
            local result, err = client.request_sync("csharp/metadata", params, 10000)
            --print(result.result.source)
            if not err then
                local bufnr, name = M.buf_from_metadata(result.result, client.id)
                -- change location name to the one returned from metadata
                -- alternative is to open buffer under location uri
                -- not sure which one is better
                loc.uri = "file://" .. name
                fetched[loc.uri] = {
                    bufnr = bufnr,
                    range = loc.range,
                }
            end
        end
    end

    return fetched
end

M.textdocument_definition_to_locations = function(result)
    if not vim.tbl_islist(result) then
        return { result }
    end

    return result
end

M.handle_locations = function(locations, offset_encoding)
    local fetched = M.get_metadata(locations)

    if not vim.tbl_isempty(fetched) then
        if #locations > 1 then
            utils.set_qflist_locations(locations, offset_encoding)
            vim.api.nvim_command("copen")
            return true
        else
            -- utils.jump_to_location(locations[1], fetched[locations[1].uri].bufnr)
            vim.lsp.util.jump_to_location(locations[1], offset_encoding)
            return true
        end
    else
        return false
    end
end

local function handle_locations_telescope(locations, offset_encoding)
    local fetched = M.get_metadata(locations)

    if not vim.tbl_isempty(fetched) then
        if #locations > 1 then
            utils.set_qflist_locations(locations, offset_encoding)
            return true
        else
            -- utils.jump_to_location(locations[1], fetched[locations[1].uri].bufnr)
            vim.lsp.util.jump_to_location(locations[1], offset_encoding)
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

local function telecope_handle(results, offset_encoding)
    local new_results = M.textdocument_definition_to_locations(results)
    handle_locations_telescope(new_results, offset_encoding)
    return new_results
end

M.telescope_definition_extension = function(err, result, ctx, _, action, params, opts)
    if err then
        vim.api.nvim_err_writeln("Error when executing " .. action .. " : " .. err.message)
        return
    end

    if result == nil then
        return
    end

    local flattened_results = {}
    if not vim.tbl_islist(result) then
        flattened_results = { result }
    end
    vim.list_extend(flattened_results, result)

    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding

    flattened_results = telecope_handle(flattened_results, offset_encoding)

    if vim.tbl_isempty(flattened_results) then
        return
    elseif #flattened_results == 1 and opts.jump_type ~= "never" then
        local current_uri = params.textDocument.uri
        local target_uri = flattened_results[1].uri or flattened_results[1].targetUri
        if current_uri ~= target_uri then
            local cmd
            local file_path = vim.uri_to_fname(target_uri)
            if opts.jump_type == "tab" then
                cmd = "tabedit"
            elseif opts.jump_type == "split" then
                cmd = "new"
            elseif opts.jump_type == "vsplit" then
                cmd = "vnew"
            elseif opts.jump_type == "tab drop" then
                cmd = "tab drop"
            end

            if cmd then
                vim.cmd(string.format("%s %s", cmd, file_path))
            end
        end

        vim.lsp.util.jump_to_location(flattened_results[1], offset_encoding, opts.reuse_win)
    else
        local locations = vim.lsp.util.locations_to_items(flattened_results, offset_encoding)
        pickers
            .new(opts, {
                prompt_title = title,
                finder = finders.new_table {
                    results = locations,
                    entry_maker = opts.entry_maker or make_entry.gen_from_quickfix(opts),
                },
                previewer = conf.qflist_previewer(opts),
                sorter = conf.generic_sorter(opts),
                push_cursor_on_edit = true,
                push_tagstack_on_edit = true,
            })
            :find()
    end
end


M.lsp_definitions = function()
    local client = M.get_csharpls_client()
    if client then
        local params = vim.lsp.util.make_position_params()
        local handler = function(err, result, ctx, config)
            ctx.params = params
            M.handler(err, result, ctx, config)
        end
        client.request("textDocument/definition", params, handler)
    end
end

return M
