using Genie, Genie.Requests, Genie.Renderer.Json 

rout("/", method = POST) do
    @show jsonpayload()
    @show rawpayload()
    json("$(jsonpayload())")
end 

up()
