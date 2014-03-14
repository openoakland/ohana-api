#require "garner/mixins/rack"

module Ohana
  class API < Grape::API

    #helpers Garner::Mixins::Rack
    use Rack::ConditionalGet
    use Rack::ETag

    resource "/" do
      # GET /
      desc "Provides hypermedia links to all top-level endpoints"
      get do
        {
          "organizations_url" => "#{ENV["API_BASE_URL"]}organizations{/organization_id}",
          "locations_url" => "#{ENV["API_BASE_URL"]}locations{/location_id}",
          "general_search_url" => "#{ENV["API_BASE_URL"]}search{?keyword,location,radius,language,kind,category,market_match}",
          "rate_limit_url" => "#{ENV["API_BASE_URL"]}rate_limit"
        }
      end
    end

    resource "locations" do
      # GET /locatons
      # GET /locations?page=2
      desc 'Returns all locations, 30 per page'
      params do
        optional :page, type: Integer, default: 1
        optional :per_page, type: Integer
      end
      get do
        #garner.options(expires_in: 30.minutes) do
          locations = Location.search(params)
          set_link_header(locations)
          locations
        #end
      end

      desc "Get the details for a specific location", {
        :notes =>
        <<-NOTE
          # Fetching a location

          You can fetch a location either by its id or by one of its slugs.
          The `slugs` field is an array containing all slugs for a particular
          location over time. Most locations will only have one slug, but it's
          possible that a few will have their name edited at some point. Since
          the API keeps track of the slug history, those locations will have
          multiple slugs.

          If using the API to display a location's details
          on a web page that will be crawled by search engines, we recommend
          setting the end of the canonical URL of the location's page to the
          last slug in the array.

          Example:

          `http://ohanapi.herokuapp.com/api/locations/521d339d1974fcdb2b002664`
          returns the same location as:
          `http://ohanapi.herokuapp.com/api/locations/southwest-branch`
        NOTE
      }
      get ':id' do
        #garner.bind(Location) do
          location = Location.find(params[:id])
          present(location, with: Entities::Location)
        #end
      end

      desc "Update a location"
      params do
        requires :id, type: String, desc: "Location ID"
      end
      put ':id' do
        authenticate!
        loc = Location.find(params[:id])
        params = request.params.except(:route_info)

        if params[:emails].present?
          params[:emails] = params[:emails].delete_if { |email| email.blank? }
        end

        loc.update_attributes!(params)
        present loc, with: Entities::Location
      end

      desc "Delete a location"
      params do
        requires :id, type: String, desc: "Location ID"
      end
      delete ':id' do
        authenticate!
        loc = Location.find(params[:id])
        loc.destroy
      end

      desc "Create a location"
      post do
        authenticate!
        loc = Location.create!(params)
        present loc, with: Entities::Location
      end

      segment '/:locations_id' do
        resource '/nearby' do
          desc "Returns locations near the one queried."
          params do
            optional :page, type: Integer, default: 1
            optional :radius, type: Float
          end

          get do
            #garner.options(expires_in: 30.minutes) do
              location = Location.find(params[:locations_id])
              nearby = Location.nearby(location, params)
              set_link_header(nearby) if location.coordinates.present?
              nearby
            #end
          end
        end

        resource '/services' do
          desc "Create a new service for this location"
          post do
            authenticate!
            location = Location.find(params[:locations_id])
            location.services.create!(params)
            location.services.last
          end
        end


        resource '/contacts' do
          desc "Delete all contacts for a location"
          params do
            requires :locations_id, type: String
          end
          delete do
            authenticate!
            loc = Location.find(params[:locations_id])
            loc.update_attributes!(contacts: [])
            loc
          end
        end
      end
    end

    resource 'organizations' do
      # GET /organizations
      # GET /organizations?page=2
      desc "Returns all organizations, 30 per page"
      params do
        optional :page, type: Integer, default: 1
      end
      get do
        #garner.options(expires_in: 30.minutes) do
          orgs = Organization.page(params[:page])
          set_link_header(orgs)
          present(orgs, with: Organization::Entity)
        #end
      end

      desc "Get the details for a specific organization", {
        :notes =>
        <<-NOTE
          # Fetching an organization

          You can fetch an organization either by its id or by one of its slugs.
          The `slugs` field is an array containing all slugs for a particular
          organization over time. Most organizations will only have one slug, but it's
          possible that a few will have their name edited at some point. Since
          the API keeps track of the slug history, those organizations will have
          multiple slugs.

          Example:

          `http://ohanapi.herokuapp.com/api/organizations/521d339d1974fcdb2b00265f`
          returns the same organization as:
          `http://ohanapi.herokuapp.com/api/organizations/ymca-of-silicon-valley`
        NOTE
      }
      get ':id' do
        #garner.bind(Organization) do
          org = Organization.find(params[:id])
          present(org, with: Organization::Entity)
        #end
      end

      desc "Update an organization", {
        :notes =>
        <<-NOTE
          ### Currently, the only organization parameter that can be updated is the name.
          Example HTTP PUT request:
          ```
          #{ENV["API_BASE_URL"]}organizations/org_id?name=new name
          ```

          Example request via our [Ruby wrapper](https://github.com/codeforamerica/ohanakapa-ruby):
          ```
          Ohanakapa.put("organizations/org_id/", :query => { :name => "new name" })
          ```
          where `org_id` is the id of the organization you want to update.

          A valid API token is required. You can get one by [registering your app](http://ohanapi.herokuapp.com).
        NOTE
      }
      params do
        requires :id, type: String, desc: "Organization ID"
        requires :name, type: String, desc: "Organization Name"
      end
      put ':id' do
        authenticate!
        org = Organization.find(params[:id])
        org.update_attributes!(name: params[:name])
        present org, with: Organization::Entity
      end

      segment '/:organization_id' do
        resource '/locations' do
          desc "Return the queried organization's locations."
          params do
            optional :page, type: Integer, default: 1
          end
          get do
            #garner.options(expires_in: 30.minutes) do
              org = Organization.find(params[:organization_id])
              locations = org.locations.page(params[:page])
              set_link_header(locations)
              present(locations, with: Entities::Location)
            #end
          end
        end
      end
    end

    resource 'services' do
      desc "Update a service"
      params do
        requires :id, type: String, desc: "Service ID"
      end
      put ':id' do
        authenticate!
        service = Service.find(params[:id])
        params = request.params.except(:route_info)

        params[:service_areas] = [] if params[:service_areas].blank?

        service.update_attributes!(params)
        service
      end

      segment '/:services_id' do
        resource '/categories' do
          desc "Update a service's categories"
          params do
            requires :category_slugs, type: Array
          end
          put do
            authenticate!
            s = Service.find(params[:services_id])

            # Create an array of category ids from the category slugs
            # that were passed in. The slugs are "URL friendly" versions
            # of the Open Eligibility (http://openeligibility.org) category
            # names.
            # For example, "Prevent & Treat" becomes "prevent-and-treat".
            # If you want to see all 327 slugs, run this command from the
            # Rails console:
            # Category.all.map(&:slugs).flatten
            cat_ids = []
            params[:category_slugs].each do |cat_slug|
              cat = Category.find(cat_slug)
              cat_ids.push(cat.id)
            end

            # Set the service's category_ids to this new array of ids
            s.category_ids = cat_ids
            s.save
            s
          end
        end
      end
    end

    resource 'categories' do
      # GET /categories
      desc "Returns all categories"
      get do
        #garner.bind(Category) do
          cats = Category.page(1).per(400)
          present cats, with: Category::Entity
        #end
      end

      segment "/:category_id" do
        resource "/children" do
          desc "Returns the category's children categories"
          params do
            requires :category_id, type: String
          end
          get do
            children = Category.find(params[:category_id]).children
            present children, with: Category::Entity
          end
        end
      end
    end

    resource 'search' do
      # GET /search?keyword={keyword}&location={loc}
      desc "Search using a variety of parameters. Returns locations.", {
        :notes =>
        <<-NOTE
          # Search

          ## Parameters

          ### keyword

          When searching by `keyword`, the API returns locations where the
          search term matches one or more of these fields:

              the location's name
              the location's description
              the location's parent organization's name
              the location's services' keywords
              the location's services' name
              the location's services' descriptions
              the location's services' category names

          Results that match service categories are ranked the highest,
          followed by service keywords matches.

          Example:
          ```
          #{ENV["API_BASE_URL"]}search?keyword=food
          ```

          ### org_name

          This parameter allows you to filter locations that belong to a
          specific organization.

          Example:
          ```
          #{ENV["API_BASE_URL"]}search?org_name=San+Mateo+County+Human+Services+Agency
          ```

          ### location, radius
          Queries that include the `location` parameter filter the results to
          only include locations that are 5 miles (by default) from the
          `location`.
          To search within a radius smaller or greater than 5 miles, use the
          `radius` parameter. `radius` must be a Float between 0.1 and 50.
          `location` can be an address (full or partial), or a 5-digit ZIP code.
          Results are sorted by distance.

          Examples:

          `#{ENV["API_BASE_URL"]}search?location=94403`

          `#{ENV["API_BASE_URL"]}search?location=san mateo&radius=10`

          `#{ENV["API_BASE_URL"]}search?keyword=emergency&location=94403`

          ### language
          The `language` parameter can be used to filter locations by language
          spoken at the location.

          Examples:

          `#{ENV["API_BASE_URL"]}search?language=tagalog`

          `#{ENV["API_BASE_URL"]}search?location=east palo alto&language=tongan`

          `#{ENV["API_BASE_URL"]}search?keyword=daycare&language=spanish`

          ### category
          The `category` parameter is used to search only on the service
          categories field using the [OpenEligibility](http://openeligibility.org) taxonomy.
          It is provided to allow targeted search results that will only return
          locations that belong to the category passed in the request. The value
          of the `category` parameter must match the OpenEligibility term spelling exactly.

          Examples:

          `#{ENV["API_BASE_URL"]}search?category=Emergency Food`

          `#{ENV["API_BASE_URL"]}search?category=Help Fill out Forms`

          To get an array containing all possible categories, you can run this
          Ruby code via our [wrapper](https://github.com/codeforamerica/ohanakapa-ruby):

          `Ohanakapa.categories.map(&:name)`

          ### kind

          The `kind` parameter can be used to filter locations by the
          overall type of organization. Possible values are (exact spelling):

              Arts
              Clinics
              Education
              Entertainment
              Farmers' Markets
              Government
              Human Services
              Libraries
              Museums
              Other
              Parks
              Sports

          Examples:

          *Single*:

          `#{ENV["API_BASE_URL"]}search?kind=Human Services`

          *Multiple*:

          `#{ENV["API_BASE_URL"]}search?kind[]=Libaries&kind[]=Parks`

          *Sort by kind (default order is "asc")*:

          `#{ENV["API_BASE_URL"]}search?kind[]=Libaries&kind[]=Parks&sort=kind`

          *Sort by kind in descending order*:

          `#{ENV["API_BASE_URL"]}search?kind[]=Libaries&kind[]=Parks&sort=kind&order=desc`

          ### market_match (Farmers' Markets only)

          Get a list of markets that participate in the [Market Match](http://www.pcfma.com/pcfma_marketmatch.php) program.

          Examples:

          `#{ENV["API_BASE_URL"]}search?kind=market&market_match=1` (to get participants)

          `#{ENV["API_BASE_URL"]}search?kind=market&market_match=0` (to get non-participants)

          ### products, payments (Farmers' Markets only)
          These two additional parameters are available for farmers' markets
          to filter the markets that only accept certain types of payment and
          sell certain kinds of products.

          Examples:

          `#{ENV["API_BASE_URL"]}search?products=Baked Goods`

          `#{ENV["API_BASE_URL"]}search?products=baked goods`

          `#{ENV["API_BASE_URL"]}search?payments=SFMNP`

          `#{ENV["API_BASE_URL"]}search?payments=snap`

          `#{ENV["API_BASE_URL"]}search?payments=SNAP&products=vegetables`

          Possible values for `payments`: Credit, WIC, WICcash, SFMNP, SNAP

          Possible values for `products`:

              Baked Goods
              Cheese
              Crafts
              Flowers
              Eggs
              Seafood
              Herbs
              Vegetables
              Honey
              Jams
              Maple
              Meat
              Nursery
              Nuts
              Plants
              Poultry
              Prepared Food
              Soap
              Trees
              Wine


          ## JSON response
          The search results JSON includes the location's parent organization
          info, as well as the location's services, so you can have all the
          info in one query instead of three.

          Search returns 30 results per page. Use the `page` parameter to
          get a new set of results.

          Example:

          `#{ENV["API_BASE_URL"]}search?keyword=education&page=2`

          Pagination info is available via the following HTTP response headers:

          `X-Total-Count`

          `X-Total-Pages`

          `X-Current-Page`

          `X-Next-Page`

          `X-Previous-Page`

          Pagination links are available via the `Link` header.
        NOTE
      }
      params do
        optional :keyword, type: String
        optional :location, type: String, desc: "An address or 5-digit ZIP code"
        optional :radius, type: Float, desc: "Distance in miles from the location parameter"
        optional :language, type: String, desc: "Languages other than English spoken at the location"
        optional :kind, type: Array, desc: "The type of organization, such as human services, farmers' markets"
        optional :category, type: String, desc: "The service category based on the OpenEligibility taxonomy"
        optional :market_match, type: String, desc: "To filter farmers' markets that participate in Market Match"
        optional :products, type: String, desc: "To filter farmers' markets that sell certain products"
        optional :payments, type: String, desc: "To filter farmers' markets that accept certain payment types"
        optional :page, type: Integer, default: 1
      end
      get do
        #garner.options(expires_in: 30.minutes) do
          locations = Location.search(params)
          set_link_header(locations)
          locations
        #end
      end
    end

    ## Uncomment this endpoint if you want to enable rate limiting.
    ## See lines 85-90 in config/application.rb
    # resource "rate_limit" do
    #   # GET /rate_limit
    #   desc "Provides rate limit info", {
    #     :notes =>
    #     <<-NOTE
    #       Rate Limiting
    #       -------------

    #       Requests that don't include an `X-Api-Token` header with a valid token
    #       are limited to 60 requests per hour. You can get a valid token by
    #       registering an app at http://ohanapi.herokuapp.com.

    #       Requests that have a valid header and token get 5000 requests per hour.

    #       You can check your rate limit via the `#{ENV["API_BASE_URL"]}rate_limit` endpoint,
    #       which won't affect your rate limit, or by examining the following
    #       response headers:

    #       `X-RateLimit-Limit` (The maximum number of requests permitted per hour.)

    #       `X-RateLimit-Remaining` (The number of requests remaining in the current rate limit window.)

    #       Once you go over the limit, you will receive a `403` response:

    #           HTTP/1.1 403 Forbidden
    #           Connection: close
    #           Content-Type: application/json
    #           Date: Thu, 12 Sep 2013 06:20:45 GMT
    #           Status: 403 Forbidden
    #           Transfer-Encoding: chunked

    #           {
    #             "description": "Rate limit exceeded",
    #             "hourly_rate_limit": 60,
    #             "method": "GET",
    #             "request": "http://localhost:8080/api/search",
    #             "status": 403
    #           }

    #       **Staying within the rate limit**

    #       If you are using a valid X-Api-Token, and you are exceeding
    #       your rate limit, you can likely fix the issue by caching API responses
    #       and using conditional requests.

    #       **Conditional requests**

    #       Most responses return an ETag header.
    #       You can use the values of that headers to make subsequent requests
    #       to those resources using the If-None-Match header.
    #       If the resource has not changed, the server will return a
    #       304 Not Modified and an empty body. Also note: making a conditional
    #       request and receiving a 304 response does not count against your
    #       Rate Limit, so we encourage you to use it whenever possible.
    #     NOTE
    #   }
    #   get do
    #     token = request.env["HTTP_X_API_TOKEN"].to_s
    #     limit = (token.present? && User.where('api_applications.api_token' => token).exists?) ? 5000 : 60
    #     {
    #       "rate" => {
    #         "limit" => limit,
    #         "remaining" => limit - (REDIS.get("throttle:#{request.ip}:#{Time.now.strftime('%Y-%m-%dT%H')}")).to_i
    #       }
    #     }
    #   end
    # end
  end
end