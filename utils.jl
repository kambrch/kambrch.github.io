function hfun_bar(vname)
  val = Meta.parse(vname[1])
  return round(sqrt(val), digits=2)
end

function hfun_m1fill(vname)
  var = vname[1]
  return pagevar("index", var)
end

function lx_baz(com, _)
  # keep this first line
  brace_content = Franklin.content(com.braces[1]) # input string
  # do whatever you want here
  return uppercase(brace_content)
end


# Macro for images:

@eval Franklin begin
  function hfun_img(args)
    path  = args[1]
    alt   = length(args) ≥ 2 ? args[2] : ""
    width = length(args) ≥ 3 ? args[3] : ""
    align = length(args) ≥ 4 ? args[4] : "center"
    class = length(args) ≥ 5 ? args[5] : ""
    class = occursin("framed", class) ? replace(class, "bordered" => "") : class


    resolved = "/" * path

    align_style = align == "left"  ? "float:left;" :
                  align == "right" ? "float:right;" :
                                     "display:block; margin-left:auto; margin-right:auto;"

    return """
    <div class="framed" style="$(align_style)">
      <img src="$(resolved)" alt="$(alt)"
           class="$(class)"
           style="width:$(width); max-width:100%; height:auto;">
    </div>
    """
  end
end
