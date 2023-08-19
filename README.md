<h1>SAMBA multi-arch image</h1>
<p>A Multi-Aarch image for lightweight, highly customizable, containerized SAMBA server</p>
<p></p>
<img alt="SAMBA" src="https://www.samba.org/samba/style/2010/grey/headerPrint.jpg">
<p>This is an unofficial multi-aarch docker image of SAMBA created for multiplatform support.This image creates a local SAMBA server to ficilitate client-side data transfer. Official Website: <a href="https://www.samba.org/" rel="nofollow noopener">https://www.samba.org/</a>
</p>
<h2>The architectures supported by this image are:</h2>
<table>
  <thead>
    <tr>
      <th align="center">Architecture</th>
      <th align="center">Available</th>
      <th>Tag</th>
       <th>Status</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center">x86-64</td>
      <td align="center">✅</td>
      <td>amd64-&lt;version tag&gt;</td>
      <td>Tested "WORKING"</td>
    </tr>
    <tr>
      <td align="center">arm64</td>
      <td align="center">✅</td>
      <td>arm64v8-&lt;version tag&gt;</td>
      <td>Tested "WORKING"</td>
    </tr>
    <tr>
      <td align="center">armhf</td>
      <td align="center">✅</td>
      <td>arm32v7-&lt;version tag&gt;</td>
      <td>Tested "WORKING"</td>
    </tr>
  </tbody>
</table>
<h2>Version Tags</h2>
<p>This image provides various versions that are available via tags. Please read the <a href="https://www.samba.org/" rel="nofollow noopener">update information</a> carefully and exercise caution when using "older versions" tags as they tend to contain unfixed bugs. </p>
<table>
  <thead>
    <tr>
      <th align="center">Tag</th>
      <th align="center">Available</th>
      <th>Description</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td align="center">latest</td>
      <td align="center">✅</td>
      <td>Stable "SAMBA releases</td>
    </tr>
    <tr>
      <td align="center">4.18.6</td>
      <td align="center">✅</td>
      <td>Static "SAMBA" build version 4.18.6</td>
    </tr>
  </tbody>
</table>
<h2>Running Image :</h2>
<p>Here are some example snippets to help you get started creating a container.</p>
<h3>docker-compose (recommended, <a href="https://itnext.io/a-beginners-guide-to-deploying-a-docker-application-to-production-using-docker-compose-de1feccd2893" rel="nofollow noopener">click here for more info</a>) </h3>
<pre><code>---
version: "3.9"
services:
  samba-server-alpine:
    image: mekayelanik/samba-server-alpine:latest
    container_name: samba-server-alpine
    environment:
      - TZ=Asia/Dhaka
      - WORKGROUP=SAMBA-Server
      - SMB_PORT=445
      - TZ=Asia/Dhaka
      - NUMBER_OF_USERS=3
      - USER_NAME_1=nahid
      - USER_PASS_1=passwordnahid1
      - USER_1_UID=1001
      - USER_1_GID=1001
      - USER_NAME_2=mekayel
      - USER_PASS_2=mekayelpass2
      - USER_2_UID=1102
      - USER_2_GID=1102
      - USER_NAME_3=anik
      - USER_PASS_3=anikpass3
      - USER_3_UID=1102
      - USER_3_GID=1102
      - NUMBER_OF_SHARES=4
      - SHARE_NAME_1=SHARE_1
      - SHARE_NAME_2=AUDIO
      - SHARE_NAME_3=CCTV-Footage
      - SHARE_NAME_4=Game-Library
      - SHARE_1_GUEST_ONLY=no
      - SHARE_2_GUEST_ONLY=no
      - SHARE_3_GUEST_ONLY=yes
      - SHARE_4_GUEST_ONLY=no
      - SHARE_1_WRITE_LIST=mekayel
      - SHARE_2_WRITE_LIST=nahid
      - SHARE_3_WRITE_LIST=anik mekayel
      - SHARE_4_WRITE_LIST=nahid
      - SHARE_1_READ_ONLY=no
      - SHARE_2_READ_ONLY=no
      - SHARE_3_READ_ONLY=yes
      - SHARE_4_READ_ONLY=no
      - SHARE_1_READ_LIST=anik
      - SHARE_2_READ_LIST=mekayel anik
      - SHARE_3_READ_LIST=anik nahid
      - SHARE_4_READ_LIST=nahid
      - SHARE_1_BROWSEABLE=yes
      - SHARE_2_BROWSEABLE=yes
      - SHARE_3_BROWSEABLE=yes
      - SHARE_4_BROWSEABLE=yes
      - SHARE_1_VALID_USERS=anik
      - SHARE_2_VALID_USERS=mekayel anik
      - SHARE_3_VALID_USERS=anik nahid
      - SHARE_4_VALID_USERS=nahid
    volumes:
      - /host/path/to/share-1:/data/SHARE_1     
      - /host/path/to/AUDIO:/data/AUDIO
      - /host/path/to/CCTV-Footage:/data/CCTV-Footage
      - /host/path/to/Game-Library:/data/Game-Library
    restart: unless-stopped
</code></pre>
<h3>docker cli ( <a href="https://docs.docker.com/engine/reference/commandline/cli/" rel="nofollow noopener">click here for more info</a>) </h3>
<pre><code>docker run -d \
  --name=samba-server-alpine \
      -e TZ=Asia/Dhaka \
      -e SMB_PORT=445 \
      -e WORKGROUP=SAMBA-Server \
      -e TZ=Asia/Dhaka \
      -e NUMBER_OF_USERS=3 \
      -e USER_NAME_1=user1 \
      -e USER_PASS_1=password1 \
      -e USER_1_UID=1001 \
      -e USER_1_GID=1001 \
      -e USER_NAME_2=user2 \
      -e USER_PASS_2=password2 \
      -e USER_2_UID=1102 \
      -e USER_2_GID=1102 \
      -e USER_NAME_3=user3 \
      -e USER_PASS_3=password3 \
      -e USER_3_UID=1102 \
      -e USER_3_GID=1102 \
      -e NUMBER_OF_SHARES=4 \
      -e SHARE_NAME_1=SHARE_1 \
      -e SHARE_NAME_2=SHARE_2 \
      -e SHARE_NAME_3=SHARE_3 \
      -e SHARE_NAME_4=SHARE_4 \
      -e SHARE_1_GUEST_ONLY=no \
      -e SHARE_2_GUEST_ONLY=no \
      -e SHARE_3_GUEST_ONLY=yes \
      -e SHARE_4_GUEST_ONLY=no \
      -e SHARE_1_WRITE_LIST=user1 \
      -e SHARE_2_WRITE_LIST=user2 \
      -e SHARE_3_WRITE_LIST=user1 user3 \
      -e SHARE_4_WRITE_LIST=user2 \
      -e SHARE_1_READ_ONLY=no \
      -e SHARE_2_READ_ONLY=no \
      -e SHARE_3_READ_ONLY=yes \
      -e SHARE_4_READ_ONLY=no \
      -e SHARE_1_READ_LIST=user2 \
      -e SHARE_2_READ_LIST=user1 user2 \
      -e SHARE_3_READ_LIST=user2 user3 \
      -e SHARE_4_READ_LIST=user1 \
      -e SHARE_1_BROWSEABLE=yes \
      -e SHARE_2_BROWSEABLE=yes \
      -e SHARE_3_BROWSEABLE=yes \
      -e SHARE_4_BROWSEABLE=yes \
      -e SHARE_1_VALID_USERS=user1 \
      -e SHARE_2_VALID_USERS=user2 user1 \
      -e SHARE_3_VALID_USERS=user3 user2 \
      -e SHARE_4_VALID_USERS=user1 \
      -v /host/path/to/SAHRE_1:/data/SHARE_1 \
      -v /host/path/to/SHARE_2:/data/SAHRE_2 \
      -v /host/path/to/SAHRE_3:/data/SAHRE_3 \
      -v /host/path/to/SAHRE_4:/data/SAHRE_4
  --restart unless-stopped \
  mekayelanik/samba-server-alpine:latest
</code></pre>

<h3>If anyone wishes to give dedicated Local IP to SAMBA container using MACVLAN ( <a href="https://docs.docker.com/network/macvlan/" rel="nofollow noopener">click here for more info</a>) </h3>
<pre><code>---
version: "3.9"
services:
  samba-server-alpine:
    image: mekayelanik/samba-server-alpine:latest
    container_name: samba-server-alpine
    environment:
      - TZ=Asia/Dhaka
      - WORKGROUP=SAMBA-Server
      - TZ=Asia/Dhaka
      - SMB_PORT=445
      - NUMBER_OF_USERS=3
      - USER_NAME_1=nahid
      - USER_PASS_1=passwordnahid1
      - USER_1_UID=1001
      - USER_1_GID=1001
      - USER_NAME_2=mekayel
      - USER_PASS_2=mekayelpass2
      - USER_2_UID=1102
      - USER_2_GID=1102
      - USER_NAME_3=anik
      - USER_PASS_3=anikpass3
      - USER_3_UID=1102
      - USER_3_GID=1102
      - NUMBER_OF_SHARES=4
      - SHARE_NAME_1=SHARE_1
      - SHARE_NAME_2=AUDIO
      - SHARE_NAME_3=CCTV-Footage
      - SHARE_NAME_4=Game-Library
      - SHARE_1_GUEST_ONLY=no
      - SHARE_2_GUEST_ONLY=no
      - SHARE_3_GUEST_ONLY=yes
      - SHARE_4_GUEST_ONLY=no
      - SHARE_1_WRITE_LIST=mekayel
      - SHARE_2_WRITE_LIST=nahid
      - SHARE_3_WRITE_LIST=anik mekayel
      - SHARE_4_WRITE_LIST=nahid
      - SHARE_1_READ_ONLY=no
      - SHARE_2_READ_ONLY=no
      - SHARE_3_READ_ONLY=yes
      - SHARE_4_READ_ONLY=no
      - SHARE_1_READ_LIST=anik
      - SHARE_2_READ_LIST=mekayel anik
      - SHARE_3_READ_LIST=anik nahid
      - SHARE_4_READ_LIST=nahid
      - SHARE_1_BROWSEABLE=yes
      - SHARE_2_BROWSEABLE=yes
      - SHARE_3_BROWSEABLE=yes
      - SHARE_4_BROWSEABLE=yes
      - SHARE_1_VALID_USERS=anik
      - SHARE_2_VALID_USERS=mekayel anik
      - SHARE_3_VALID_USERS=anik nahid
      - SHARE_4_VALID_USERS=nahid
    volumes:
      - /host/path/to/share-1:/data/SHARE_1     
      - /host/path/to/AUDIO:/data/AUDIO
      - /host/path/to/CCTV-Footage:/data/CCTV-Footage
      - /host/path/to/Game-Library:/data/Game-Library
    restart: unless-stopped
        hostname: samba-server
    domainname: local
    mac_address: 54-64-34-24-14-04
    networks:
      macvlan-1:
        ipv4_address: 192.168.1.45
#### Network Defination ####
networks:
  macvlan-1:
    name: macvlan-1
    external: True
    driver: macvlan
    driver_opts:
      parent: eth0
    ipam:
      config:
        - subnet: "192.168.1.0/24"
          ip_range: "192.168.1.2/24"
          gateway: "192.168.1.1"
</code></pre>
<h2>Updating Info</h2>
<p>Below are the instructions for updating containers:</p>
<h3>Via Docker Compose (recommended)</h3>
<ul>
  <li>Update all images: <code>docker compose pull</code>
    <ul>
      <li>or update a single image: <code>docker compose pull mekayelanik/samba-server-alpine</code>
      </li>
    </ul>
  </li>
  <li>Let compose update all containers as necessary: <code>docker compose up -d</code>
    <ul>
      <li>or update a single container (recommended): <code>docker compose up -d samba-server-alpine</code>
      </li>
    </ul>
  </li>
  <li>To remove the old unused images run: <code>docker image prune</code>
  </li>
</ul>
<h3>Via Docker Run</h3>
<ul>
  <li>Update the image: <code>docker pull mekayelanik/samba-server-alpine:latest</code>
  </li>
  <li>Stop the running container: <code>docker stop samba-server-alpine</code>
  </li>
  <li>Delete the container: <code>docker rm samba-server-alpine</code>
  </li>
  <li>Recreate a new container with the same docker run parameters as instructed above (if mapped correctly to a host folder, your <code>/AgentDVR/Media/XML</code> folder and settings will be preserved) </li>
  <li>To remove the old unused images run: <code>docker image prune</code>
  </li>
</ul>
<h3>Via <a href="https://containrrr.dev/watchtower/" rel="nofollow noopener">Watchtower</a> auto-updater (only use if you don't remember the original parameters)</h3>
<ul>
  <li>
    <p>Pull the latest image at its tag and replace it with the same env variables in one run:</p>
    <pre>
<code>docker run --rm \
-v /var/run/docker.sock:/var/run/docker.sock \
containrrr/watchtower\
--run-once samba-server-alpine</code></pre>
  </li>
  <li>
    <p>To remove the old unused images run: <code>docker image prune</code>
    </p>
  </li>
</ul>
<p>
  <strong>Note:</strong> You can use <a href="https://containrrr.dev/watchtower/" rel="nofollow noopener">Watchtower</a> as a solution to automated updates of existing Docker containers. But it is discouraged to use automated updates. However, this is a useful tool for one-time manual updates of containers where you have forgotten the original parameters. In the long term, it is recommend to use <a href="https://itnext.io/a-beginners-guide-to-deploying-a-docker-application-to-production-using-docker-compose-de1feccd2893" rel="nofollow noopener">Docker Compose</a>.
</p>
<h3>Image Update Notifications - Diun (Docker Image Update Notifier)</h3>
<ul>
  <li>You can also use <a href="https://crazymax.dev/diun/" rel="nofollow noopener">Diun</a> for update notifications. Other tools that automatically update containers unattended are not encouraged </li>
</ul>
<h2>Issues & Requests</h2>
<p> To submit this Docker image specific issues or requests visit this docker image's Github Link: <a href="https://github.com/MekayelAnik/samba-server-alpine" rel="nofollow noopener">https://github.com/MekayelAnik/samba-server-alpine</a>
</p>
<p> For SAMBA related issues and requests, please visit: <a href="https://github.com/samba-team/samba" rel="nofollow noopener">https://github.com/samba-team/samba</a>
</p>