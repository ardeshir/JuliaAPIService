using Genie, Genie.Requests, Genie.Renderer.Json 

route("/", method = POST) do
    @show jsonpayload()
    @show rawpayload()
    json("$(jsonpayload())")
end 

up()
