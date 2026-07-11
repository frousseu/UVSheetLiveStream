
#!/bin/bash

# 1. Get an access token (interactive OAuth, one-time setup)
# 2. Exchange for JWT
curl -X GET "https://www.inaturalist.org/users/api_token" -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# 3. Use the JWT to score an image
curl -X POST "https://api.inaturalist.org/v1/computervision/score_image" \
  -H "Authorization: YOUR_JWT" \
  -F "image=@insect_photo.jpg" \
  -F "lat=45.5" \
  -F "lng=-73.6" \
  -F "observed_on=2026-07-10"