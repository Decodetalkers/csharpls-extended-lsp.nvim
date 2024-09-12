local csharpls_extend = require("csharpls_extended")

local make_entry = require("telescope.make_entry")
local pickers = require("telescope.pickers")
local conf = require("telescope.config").values
local finders = require("telescope.finders")

local M = {
    title = "csharpls definition"
};

M.telescope_handle_location = function(locations, offset_encoding, opts)
    local fetched = csharpls_extend.get_metadata(locations, offset_encoding)

    if vim.tbl_isempty(fetched) then
        vim.notify("No locations found")
        return
    end
    if #locations == 1 then
        vim.lsp.util.jump_to_location(fetched[1], offset_encoding)
        return
    end

    pickers
        .new(opts, {
            prompt_title = M.title,
            finder = finders.new_table({
                results = fetched,
                entry_maker = opts.entry_maker or make_entry.gen_from_quickfix(opts),
            }),
            previewer = conf.qflist_previewer(opts),
            sorter = conf.generic_sorter(opts),
            push_cursor_on_edit = true,
            push_tagstack_on_edit = true,
        })
        :find()
end

M.telescope_handle = function(err, result, ctx, config, opts)
    -- fixes error for "jump_to_location must be called with valid offset
    -- encoding"
    -- https://github.com/neovim/neovim/issues/14090#issuecomment-1012005684
    local offset_encoding = vim.lsp.get_client_by_id(ctx.client_id).offset_encoding
    local locations = csharpls_extend.textdocument_definition_to_locations(result)
    M.telescope_handle_location(locations, offset_encoding, opts)
end

M.csharpls_decompile_telescope = function(opts)
    local client = csharpls_extend.get_csharpls_client()
    if client then
        local params = vim.lsp.util.make_position_params()
        local handler = function(err, result, ctx, config)
            ctx.params = params
            M.telescope_handle(err, result, ctx, config, opts)
        end
        client.request("textDocument/definition", params, handler)
    end
end


return require("telescope").register_extension({
    exports = {
        csharpls_decompile_definition = M.csharpls_decompile_telescope,
    },
})
