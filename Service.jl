using HTTP  
using JSON  
using Logging  

const SERVER = Ref{HTTP.Servers.Server}()
const ROUTER = HTTP.Router()
  
include("Solver.jl")  
using .Solver  
  
# Function to handle the index route  
function index_handler(req::HTTP.Request)  
    return HTTP.Response(200, JSON.json("Welcome to the GloPar Service!")) 
end  
  
# Function to handle the health check route  
function health_handler(req::HTTP.Request)  
    return HTTP.Response(200, JSON.json("OK"))  
end  
  
# Function to handle the /glopar/v2 POST route  
function glopar_handler(req::HTTP.Request)  
    try  
        # Read and parse the JSON body  
        body = String(req.body)  
          
        # Process the data using the Solver function  
        response_json = Solve(body)  
          
        return HTTP.Response(200, JSON.json(response_json)) 
    catch e  
        return HTTP.Response(400, JSON.json("Bad Request: $(e)"))  
    end  
end  
  
# Function to start the server with configurable host and port  
function start_server()  
    # Get the host and port from environment variables with defaults  
    host = get(ENV, "SERVER_HOST", "0.0.0.0")  
    port = parse(Int, get(ENV, "SERVER_PORT", "8000"))  
      
    # Define the router  
    #router = HTTP.Router()  
  
    # Register routes  
    HTTP.register!(ROUTER, "GET", "/", index_handler)  
    HTTP.register!(ROUTER, "GET", "/health", health_handler)  
    HTTP.register!(ROUTER, "POST", "/glopar/v2", glopar_handler)  
      
    # Log the server start  
    @info "Starting server on $host:$port"  
      
    # Start the server  
    SERVER[] = HTTP.serve(ROUTER, host, port)  
end  
  
# Start the server  
start_server()  
