using HTTP, JSON3

const SERVER = Ref{HTTP.Servers.Server}()
const SERVER_ROUTER = HTTP.Router()

find_square(n) = n*n
function find_square_req(req)
    data = JSON3.read(req.body, Dict)
    n = data["number"]
    return HTTP.Response(200, JSON3.write(Dict("number" => n, "square" => find_square(n))))
end

HTTP.register!(SERVER_ROUTER, "POST", "/api/find_square_req", find_square_req)

function live(req)
    return HTTP.Response(200, JSON3.write("OK"))
end

HTTP.register!(SERVER_ROUTER, "GET", "/api/live", live)

function run()
    SERVER[] = HTTP.serve(SERVER_ROUTER, "0.0.0.0", 3000)
end

run()