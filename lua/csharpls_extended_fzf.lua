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
    opts = opts or {}

    if vim.tbl_isempty(fetched) then
        vim.notify("No locations found")
        return
    end

    if #locations == 1 then
        vim.lsp.util.show_document(fetched[1], offset_encoding, { focus = true })
        return
    end

    -- vim.print(fetched)
    fzf.fzf_exec(function(cb)
        for i, loc in pairs(fetched) do
            cb(loc.filename .. "@" .. loc.lnum)
        end
        cb()
    end, {
        prompt = "csharpls: ",
        actions = {
            ["default"] = function(arg, o)
                vim.print("TAKING ACTION")
                vim.print(arg)
                local splits = vim.split(arg[1], "@")
                local path = splits[1]
                local lineNum = splits[2]
                local location = nil
                for _, loc in pairs(fetched) do
                    if loc.filename == path and loc.lnum == tonumber(lineNum) then
                        location = loc
                        break
                    end
                end
                if location ~= nil then
                    vim.lsp.util.show_document(location, offset_encoding, { focus = true })
                else
                    vim.print("ERROR: location not found in results: ")
                    vim.print(arg)
                    vim.print(fetched)
                end
            end
        },
        previewer = "builtin",
    })
end

M.fzf_handle = function(_, result, ctx, _, opts)
    vim.print("csharpls_handle")
    -- fixes error for "jump_to_location must be called with valid offset
    -- encoding"
    -- https://github.com/neovim/neovim/issues/14090#issuecomment-1012005684
    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    local locations = csharpls_extend.textdocument_definition_to_locations(result)
    M.fzf_handle_location(locations, offset_encoding, opts)
end

M.fzf = function(opts)
    vim.print("csharpls_fzf")
    local client = csharpls_extend.get_csharpls_client()
    if client then
        vim.print("csharpls_fzf has client")
        local params
        params = vim.lsp.util.make_position_params(0, 'utf-8')
        vim.print("csharpls_fzf params: " .. tostring(params))
        local handler = function(err, result, ctx, config)
            vim.print("csharpls_handler")
            ctx.params = params
            M.fzf_handle(err, result, ctx, config, opts)
        end
        client:request("textDocument/definition", params, handler, 0)
    end
end

return M
