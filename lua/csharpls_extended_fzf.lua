local csharpls_extend = require("csharpls_extended")
local fzf = require("fzf-lua")

local M = {
    title = "csharpls definition"
};

--- @param locations lsp.Location[] | lsp.LocationLink[]
--- @param offset_encoding string
--- @param opts any
M.fzf_handle_location = function(locations, offset_encoding, opts)
    local fetched = csharpls_extend.get_metadata(locations, offset_encoding)
    local lines = {}
    for i, loc in pairs(fetched) do
        loc.index = i
        local path = vim.split(loc.filename, '/', { trimempty = true })
        local filename = path[#path]
        table.insert(lines, tostring(i) .. '\t' .. filename .. ": " .. vim.trim(loc.text))
    end

    opts = opts or {}

    if vim.tbl_isempty(fetched) then
        vim.notify("No locations found")
        return
    end

    if #locations == 1 then
        vim.lsp.util.show_document(fetched[1], offset_encoding, { focus = true })
        return
    end

    -- Custom previewer that uses csharpls_extended api to generate a buffer for the
    -- preview window
    local builtin = require("fzf-lua.previewer.builtin")
    local CSharpLSExPreviewer = builtin.base:extend()

    function CSharpLSExPreviewer:new(o, popts, fzf_win)
        CSharpLSExPreviewer.super.new(self, o, popts, fzf_win)
        setmetatable(self, CSharpLSExPreviewer)
        return self
    end

    function CSharpLSExPreviewer:populate_preview_buf(entry_str)
        local location = GetLocationFromEntryBuf(entry_str, fetched)
        if (location ~= nil) then
            local tmpbuf = self:get_tmp_buffer()
            csharpls_extend.gen_virtual_file(location.filename, tmpbuf)
            self:set_preview_buf(tmpbuf)
            self.win:update_preview_scrollbar()
            -- vim.print(self.win.preview_winid)
            -- vim.print(location)

            vim.api.nvim_win_set_cursor(self.win.preview_winid, { location.lnum, location.col })
        else
            vim.print("csharpls_extended: ERROR: location is nil")
        end
    end

    -- Disable line numbering and word wrap
    function CSharpLSExPreviewer:gen_winopts()
        local new_winopts = {
            wrap   = true,
            number = true
        }
        return vim.tbl_extend("force", self.winopts, new_winopts)
    end

    function GetLocationFromIndex(strIndex, array)
        vim.print("GetLocationFromIndex: ")
        local index = tonumber(strIndex)
        for _, loc in pairs(array) do
            if loc.index == index then
                return loc
            end
        end
        return nil
    end

    function GetLocationFromEntryBuf(buf, array)
        local index, _ = unpack(vim.split(buf, '\t', { trimempty = true }))
        return GetLocationFromIndex(index, array)
    end

    fzf.fzf_exec(
        lines, {
            fzf_opts = { ['--delimiter'] = '\t', ['--with-nth'] = '2' },
            prompt = "csharpls: ",
            actions = {
                ["default"] = function(arg, _)
                    local selection = arg[1]
                    local location = GetLocationFromEntryBuf(selection, fetched)
                    if location ~= nil then
                        vim.lsp.util.show_document(location, offset_encoding, { focus = true })
                    else
                        vim.print("csharpls_extended: ERROR: location not found in results: ")
                    end
                end
            },
            previewer = CSharpLSExPreviewer,
            layout = {
                preset = "telescope"
            }
        })
end

M.fzf_handle = function(_, result, ctx, _, opts)
    -- vim.print("csharpls_handle")
    -- fixes error for "jump_to_location must be called with valid offset
    -- encoding"
    -- https://github.com/neovim/neovim/issues/14090#issuecomment-1012005684
    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    local locations = csharpls_extend.textdocument_definition_to_locations(result)
    M.fzf_handle_location(locations, offset_encoding, opts)
end

M.fzf = function(opts)
    -- vim.print("csharpls_fzf")
    local client = csharpls_extend.get_csharpls_client()
    if client then
        -- vim.print("csharpls_fzf has client")
        local params = vim.lsp.util.make_position_params(0, 'utf-8')
        -- vim.print("csharpls_fzf params: " .. tostring(params))
        local handler = function(err, result, ctx, config)
            -- vim.print("csharpls_handler")
            ctx.params = params
            -- vim.print(params)
            M.fzf_handle(err, result, ctx, config, opts)
        end
        client:request("textDocument/definition", params, handler, 0)
    else
        vim.print("csharpls_extended: ERROR: Client not found")
    end
end

return M
